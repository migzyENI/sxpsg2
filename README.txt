Static XHTML Portal Site Generator 2.3250.0perl
# Hash update!
# Use argument -h to see 3 new features that were half assed! Yummy!

DEPENDECIES:
 JSON, URI, Getopt::Long, HTML::Tiny, Path::Tiny, LWP::UserAgent ( CryptoX for page cryptography )

For Fedora:
```
	dnf install \
	perl \
	perl-JSON.noarch \
	perl-URI.noarch \
	perl-Getopt-Long.noarch \
	perl-HTML-Tiny.noarch \
	perl-Path-Tiny.noarch \
	perl-libwww-perl.noarch
```


TO RUN:
```
	$ perl sxpsg2.perl -h #show help
	$ perl sxpsg2.perl -d configuration -c portal_config.json -l portal_list.json #build site
    BASH$ ./makeportal.sh portal_config.json portal_list.json "YOUR_KEY_HERE"
```

Sample Configurations:
```
      Configuration JSON format (portal_config.json):
      {
     "version": 4,
        "title": "Portal Title",
        "media-path": "media",
        "template-path": "template",
        "template": "standard_template.htm",
        "html-version": "5",
        "output-file": "portal.html",
        "favicon-size": 32,
        "favicon-provider": "direct",
        "primary-color": "#007bff",
        "secondary-color": "#6c757d",
        "text-primary": "#333",
        "text-secondary": "#666",
        "bg-primary": "#f8f9fa",
        "bg-secondary": "#ffffff",
        "border-color": "transparent",
        "scrollbar-color": "#888"
      }
```

```
      Portal Site JSON format (portal_list.json):
      {
        "version": 3,
        "list": [
          {
            "category": "Category Name",
            "articles": [
              {
                "url": "https://example.com",
                "name": "Example Site",
                "althypers": [
                  {
                    "alturl": "https://alternate.example.com",
                    "altname": "Alternate Name"
                  }
                ]
              }
            ]
          }
        ]
      }
```

Current Todos:

Implement proper XML validation and add support for XHTML versions (IK IK but building towards strictness is easier.) -- still not done

More Providers should be added -- doesn't matte rmuch

Refactor code a little for future expansion. -- well claude is a bitch and a half.


