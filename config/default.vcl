vcl 4.0;
import std;
import directors;

# This Varnish VCL has been adapted from the Four Kitchens VCL for Varnish 3.
# This VCL is for using cache tags with drupal 8. Minor chages of VCL provided by Jeff Geerling.

backend default {
    .host = "{{.NGINX_HOSTNAME}}";
    .port = "8082";
    .first_byte_timeout = 600s;
}

# Allow private networks to purge
acl purge {    
    "127.0.0.1";        
    "10.0.0.0"/8;     
    "172.16.0.0"/12;
    "192.168.0.0"/16;
}

# Respond to incoming requests.
sub vcl_recv {
    # Add an X-Forwarded-For header with the client IP address.
    if (req.restarts == 0) {
        if (req.http.X-Forwarded-For) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        }
        else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    if (req.method == "PURGEALL") {    
        if (("{{.VARNISH_PURGE_KEY}}" ~ "^\w{23,}\b") && (req.http.X-Purge-Key != "{{.VARNISH_PURGE_KEY}}")) {
            return (synth(405, "Not allowed. Invalid Purge Key Supplied"));
        }        
        if (!client.ip ~ purge) {
            return (synth(405, "Not allowed."));
        }        
        ban("req.http.host ~ .*");
        return (synth(200, "Complete cache purged"));        
    }
    
    if (req.method == "BAN") {
        if (("{{.VARNISH_PURGE_KEY}}" ~ "^\w{23,}\b") && (req.http.X-Purge-Key != "{{.VARNISH_PURGE_KEY}}")) {
            return (synth(405, "Not allowed. Invalid Purge Key Supplied"));
        }        
        if (!client.ip ~ purge) {
            return (synth(405, "Not allowed."));
        }                       
        
        if (req.http.Purge-Cache-Tags) {
            ban("obj.http.Purge-Cache-Tags ~ " + req.http.Purge-Cache-Tags);
        }
        else {
            return (synth(403, "Purge-Cache-Tags header missing."));
        }

        # Throw a synthetic page so the request won't go to the backend.
        return (synth(200, "Ban added."));
    }

    # Only cache GET and HEAD requests (pass through POST requests).
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Don't cache logged in users
    if (req.http.Authorization) {    
        return (pass);
    }
    if (req.url ~ "^/status\.php$" ||
        req.url ~ "^/update\.php" ||
        req.url ~ "^/install\.php" ||
        req.url ~ "^/apc\.php$" ||
        req.url ~ "^/admin" ||
        req.url ~ "^/admin/.*$" ||
        req.url ~ "^/user" ||
        req.url ~ "^/user/.*$" ||
        req.url ~ "^/users/.*$" ||
        req.url ~ "^/info/.*$" ||
        req.url ~ "^/flag/.*$" ||
        req.url ~ "^.*/ajax/.*$" ||
        req.url ~ "^.*/ahah/.*$" ||
        req.url ~ "^/system/files/.*$") {
            return (pass);  
    }

    # Reject definitively non-Drupal and non-friendly URLs
    if (req.url == "(?i)^autodiscover/autodiscover.xml$" || 
        req.url == "(?i)^wp-login.php$" || 
        req.url == "(?i)^web.config$" || 
        req.url == "(?i)^wp-admin.*$") {
            return (synth(404));
    }

    # Remove all cookies that Drupal doesn't need to know about. We explicitly
    # list the ones that Drupal does need, the SESS and NO_CACHE. If, after
    # running this code we find that either of these two cookies remains, we
    # will pass as the page cannot be cached.
    if (req.http.Cookie) {
        # 1. Append a semi-colon to the front of the cookie string.
        # 2. Remove all spaces that appear after semi-colons.
        # 3. Match the cookies we want to keep, adding the space we removed
        #    previously back. (\1) is first matching group in the regsuball.
        # 4. Remove all other cookies, identifying them by the fact that they have
        #    no space after the preceding semi-colon.
        # 5. Remove all spaces and semi-colons from the beginning and end of the
        #    cookie string.
        set req.http.Cookie = ";" + req.http.Cookie;
        set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
        set req.http.Cookie = regsuball(req.http.Cookie, ";(SESS[a-z0-9]+|SSESS[a-z0-9]+|NO_CACHE)=", "; \1=");
        set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

        if (req.http.Cookie == "") {
            # If there are no remaining cookies, remove the cookie header. If there
            # aren't any cookie headers, Varnish's default behavior will be to cache
            # the page.
            unset req.http.Cookie;
        }
        else {
            # If there is any cookies left (a session or NO_CACHE cookie), do not
            # cache the page. Pass it on to Apache directly.            
            return (pass);
        }
    }

    # Optionally bypass the cache for all other request types.
    if ("{{.VARNISH_BYPASS}}" == "true") {
        set req.http.X-Varnish-Bypass = "BYPASS";
        return (pass);
    }
}

# Set a header to track a cache HITs and MISSes.
sub vcl_deliver {
    # Remove ban-lurker friendly custom headers when delivering to client.
    unset resp.http.X-Url;
    unset resp.http.X-Host;
    
    # Comment these for easier Drupal cache tag debugging in development.
    unset resp.http.Purge-Cache-Tags;
    unset resp.http.X-Drupal-Cache-Contexts;
    
    # Remove insecure headers
    unset resp.http.X-Generator;
    unset resp.http.X-Powered-By;
    unset resp.http.Server;    
    unset resp.http.X-Varnish;        

    # Apply an X-Frame-Options header if one is missing
    if (!resp.http.X-Frame-Options) {
      set resp.http.X-Frame-Options = "SAMEORIGIN";
    } 

    # Apply an X-XSS-Protection header if one is missing
    if (!resp.http.X-XSS-Protection) {
      set resp.http.X-XSS-Protection = "1; mode=block";
    } 

    # Apply a strict ReferrerPolicy header if one is missing
    if (!resp.http.Referrer-Policy) {
      set resp.http.Referrer-Policy = "same-origin";
    } 
    
    if (obj.hits > 0) {
        set resp.http.X-Varnish-Cache = "HIT";
    }
    else {
        set resp.http.X-Varnish-Cache = "MISS";
    }    

    if (req.http.X-Varnish-Bypass == "BYPASS") {
        set resp.http.X-Varnish-Cache = "BYPASS";
    }
}

# Instruct Varnish what to do in the case of certain backend responses (beresp).
sub vcl_backend_response {
    # Set ban-lurker friendly custom headers.
    set beresp.http.X-Url = bereq.url;
    set beresp.http.X-Host = bereq.http.host;

    # Don't allow static files to set cookies.
    # (?i) denotes case insensitive in PCRE (perl compatible regular expressions).
    # This list of extensions appears twice, once here and again in vcl_recv so
    # make sure you edit both and keep them equal.
    if (bereq.url ~ "(?i)\.(pdf|asc|dat|txt|doc|xls|ppt|tgz|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
        unset beresp.http.set-cookie;
    }

    # Allow items to remain in cache up to 1 hour past their cache expiration.
    set beresp.grace = 1h;
}

