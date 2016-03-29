# Varnish-3.0.7-Config
This is a basic, slimmed down variation of my own configuration. I have developed this over many months.
This is more a WordPress specific VCL with extra code to help make WooCommerce work better as it didn't seem to work correctly when adding items to the cart using the code WooThemes suggest.


I have added code which helps the purging of WordPress widgets when using the Varnish HTTP Purge plugin as just a normal Purge request would not work.


If you think I could improve on this or I have missed out something vital then please do a pull request!
