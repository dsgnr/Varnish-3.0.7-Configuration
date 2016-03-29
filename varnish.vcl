backend default {
  .host = "public-IP";
  .port = "port-number";
}

acl purge { "localhost"; "127.0.0.1"; "public-IP";}



sub vcl_recv {

	# COMMENT TO BYPASS CACHE AND GO STRAIGHT TO BACKEND
	#return (pass);
	
	# Set grace period of 2 minutes
	set req.grace = 120s;
	
		
	if (req.request == "PURGE") {
	if (!client.ip ~purge){
		error 405 "Not allowed";
	}
	
	ban("req.http.host == " +req.http.host+" && req.url ~ "+req.url);
		error 200 "Ban added";
	}
	  
	# Send proper IP addresses    
	if (req.http.x-forwarded-for) {
		set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
	} else {
	    set req.http.X-Forwarded-For = client.ip;
	}

	# Don't cache when authorization header is being provided by client
	if (req.http.Authorization || req.http.Authenticate) {
		return(pass);
	}
	
	# don't cache logged-in users or authors
	if (req.http.Cookie ~ "wp-postpass_|wordpress_logged_in_|comment_author|PHPSESSID") {
		return(pass);
	}  
		    
		    
	# Remove Google Analytics and Piwik cookies everywhere
	if (req.http.Cookie) {
		set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(__[a-z]+|has_js)=[^;]*", "");
		set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_pk_(ses|id)[\.a-z0-9]*)=[^;]*", "");
	}
	
	# Remove the cookie when it's empty
	if (req.http.Cookie == "") {
		remove req.http.Cookie;
	}
		  
	if (req.request == "PURGE") {
		if (!client.ip ~ purge) {
			error 405 "Not allowed.";
		}
		return (lookup);
	}
		
		
	# Allows for contact forms and other requests to be handled correctly
	if (req.request != "GET" && req.request != "HEAD" && req.request != "PUT" && req.request != "POST" && req.request != "TRACE" && req.request != "OPTIONS" && req.request != "DELETE") { 
		return (pipe); 
	} 
		
	if (req.request != "GET" && req.request != "HEAD") { 
		return (pass); 
	} 
		
	return (lookup); 
		
		 
	# Remove has_js and CloudFlare/Google Analytics __* cookies and statcounter is_unique
		set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js|is_unique)=[^;]*", "");
	# Remove a ";" prefix, if present.
		set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");
		 
	
	# Always cache the following file types for all users.
	if ( req.url ~ "(?i)\.(png|gif|jpeg|jpg|ico|swf|css|js|html|htm)(\?[a-z0-9]+)?$" ) {
		unset req.http.cookie;
	}
		    
		    
		 
	# Don't serve cached pages to logged in users
	if ( req.http.cookie ~ "wordpress_logged_in" || req.url ~ "vaultpress=true" ) {
		return( pass );
	}
	
	# Drop any cookies sent to WordPress.
	if ( ! ( req.url ~ "wp-(login|admin)" ) ) {
		unset req.http.cookie;
	}
		
	# Handle compression correctly. Different browsers send different
	# "Accept-Encoding" headers, even though they mostly all support the same
	# compression mechanisms. By consolidating these compression headers into
	# a consistent format, we can reduce the size of the cache and get more hits.
	if ( req.http.Accept-Encoding ) {
		
	if ( req.http.Accept-Encoding ~ "gzip" ) {
		# If the browser supports it, we'll use gzip.
		set req.http.Accept-Encoding = "gzip";
	}
		
	else if ( req.http.Accept-Encoding ~ "deflate" ) {
		# Next, try deflate if it is supported.
		set req.http.Accept-Encoding = "deflate";
	}
		
	else {
	# Unknown algorithm. Remove it and send unencoded.
		unset req.http.Accept-Encoding;
	}
		
	}	
	
	
	# accept purges from w3tc and varnish http purge
	if (req.request == "PURGE") {
	return (lookup);
	}
	#
	# don't cache search results
	if( req.url ~ "\?s=" ){
	return (pass);
	}
	
	
	# Either the admin pages or the login
	if (req.url ~ "/wp-(login|admin|cron|cart|my-account|checkout|addons)") {
	# Don't cache, pass to backend
	return (pass);
	}
	
	if ( req.url ~ "\?add-to-cart=" ) {
	 return (pass);
	}
	
	# Check the cookies for wordpress-specific items
	if (req.http.Cookie ~ "wordpress_" || req.http.Cookie ~ "comment_" || req.http.Cookie ~ " woocommerce_") {
	# A wordpress specific cookie has been set
	return (pass);
	}
	 
	 
	# allow PURGE from localhost
	if (req.request == "PURGE") {
	if (!client.ip ~ purge) {
	error 405 "Not allowed.";
	}
	return (lookup);
	}
	 
	# Force lookup if the request is a no-cache request from the client
	if (req.http.Cache-Control ~ "no-cache") {
	return (pass);
	}
	 
	# Try a cache-lookup
	return (lookup);
	 
}
 
sub vcl_fetch {
	
	# Cache everything that doesn't have specified time for 3 days!	
	set beresp.ttl   = 259200s;	
	
	if (beresp.status == 403 || beresp.status >= 500) {
	  set beresp.saintmode = 10s;
	  return (restart);
	}
	
	if (beresp.status == 404) {
	  set beresp.saintmode = 10s;
	return (hit_for_pass);
	}
	
	# Only cache status ok
	if ( beresp.status != 200 ) {
	return (hit_for_pass);
	}
	
	# Don't cache search results
	if( req.url ~ "\?s=" ){
	return (hit_for_pass);
	}
		
	# WOOCOMMERCE FIX
	# Testing showed that items weren't being stored in cart correctly.
	# The below will check for the items_in_cart cookie and return to backend if items are in cart
	# If no items in cart, or removed from cart then caching resumes
	if (req.http.Cookie ~ "woocommerce_items_in_cart") {
	# A wordpress specific cookie has been set
	return (hit_for_pass);
	}
	
	
	# Drop any cookies WordPress tries to send back to the client.
	if (  req.url ~ "wp-(login|admin)" &&  req.http.cookie ~ "wordpress_logged_in" ) {
		unset beresp.http.set-cookie;
		return (hit_for_pass);
	}
	
	# Don't serve cached pages to logged in users
	if ( req.http.cookie ~ "wordpress_") {
		return( hit_for_pass );
	}
	
	# Remove cookies               
	if (req.url ~ "\.(css|js|html|htm|php|woff)$") {
		unset beresp.http.cookie;
	}        
	        
	return (deliver);            
                
}
 
 
sub vcl_hit {
if (req.request == "PURGE") {
purge;
error 200 "Purged.";
}
}
 
sub vcl_miss {
if (req.request == "PURGE") {
purge;
error 200 "Purged.";
}
}





sub vcl_deliver {

	# Add expires headers - this is instead of entering into .htaccess
	# Stores cache of JS and CSS files on users computer for 7 days
	# Stores cache of images and fonts on users computer for 30 days
	if (req.url ~ "\.(js|css)") {
	  set resp.http.Cache-Control = "max-age=604800, public, must-revalidate";
	} else if (req.url ~ "\.(jpg|jpeg|png|gif|ico|tiff|woff|tif|bmp|ppm|pgm|xcf|psd|webp|svg)") {
	  set resp.http.Cache-Control = "max-age=2592000, public";
	} 
	
	
	# Display hit or miss headers        
	if (obj.hits > 0) {
		set resp.http.X-Cache = "HIT";
	} else {
		set resp.http.X-Cache = "MISS";
	}
   
}