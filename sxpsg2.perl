#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use JSON;
use URI;
use Getopt::Long;
use HTML::Tiny;
use Path::Tiny;
use LWP::UserAgent;

our $SXPSG_VERSION = '2.2250.250perl';

our $config_normative; #JSON FILE NAME
our $portal_list_normative; #JSON FILE NAME

our %config; #COMPLETE CARRIER
our %portal_list; #COMPLETE CARRIER

our $SXPSG_LOGGING_ENABLED = 0;
our $FAVICON_FALLBACK_ENABLED = 1;
our $media_folder = 'media'; #DIR
our $configuration_folder = 'configuration'; #DIR
our $template_folder = 'template'; #DIR

our %sxpsg_dirs; #ALL DIRS

sub main {
    %sxpsg_dirs = (
    'm' => $media_folder,
    'c' => $configuration_folder,
    't' => $template_folder,
    );

    print "SXPSG ver.$SXPSG_VERSION\n";
    enviroment_validity();
    page_create();
}

sub page_create {
    favicon_coroutine($portal_list{list}, $config{'media-path'}, $config{'favicon-provider'});

    my @sections_html;
    my $media_path = $config{'media-path'} || 'media';

    foreach my $category (@{$portal_list{list}}) {
        push @sections_html, section_create($category, $media_path);
    }

    my %replacements = (
        '__TITLE__' => $config{'title'} || 'Portal',
        '__FAVICON_SIZE__' => $config{'favicon-size'} || 32,
        '__PRIMARY_COLOUR__' => $config{'primary-color'} || '#007bff',
        '__SECONDARY_COLOUR__' => $config{'secondary-color'} || '#6c757d',
        '__TEXT_PRIMARY__' => $config{'text-primary'} || '#333',
        '__TEXT_SECONDARY__' => $config{'text-secondary'} || '#666',
        '__BG_PRIMARY__' => $config{'bg-primary'} || '#ffffff',
        '__BG_SECONDARY__' => $config{'bg-secondary'} || '#f8f9fa',
        '__BORDER_COLOUR__' => $config{'border-color'} || '#eee',
        '__SCROLLBAR_COLOUR__' => $config{'scrollbar-color'} || '#888',
        '__SECTIONS__' => join("\n", @sections_html),
    );

    my $template_file = path($config{'template-path'} || 'template',
                             $config{'template'} || 'standard_template.htm');
    my $template_content = $template_file->slurp_utf8;

    foreach my $key (keys %replacements) {
        $template_content =~ s/\Q$key\E/$replacements{$key}/g;
    }

    my $output_path = path($config{'output-file'} || 'portal.html');
    $output_path->spew_utf8($template_content);

    print("Generated: $output_path\n");
    return;
}

sub section_create {
    # Generate HTML section for a category of links
    # category_data: {
    #   category => "Category Name",
    #   articles => [
    #     { url => "...", name => "...", althypers => [...] },
    #     ...
    #   ]
    # }
    # media_path: directory path for favicon files

    my ($category_data, $media_path) = @_;

    my $h = HTML::Tiny->new;
    my @articles_html;

    if ($category_data->{articles} && @{$category_data->{articles}}) {
        foreach my $article (@{$category_data->{articles}}) {
            push @articles_html, link_create($h, $article, $media_path);
        }
    }

    return $h->tag('section', { class => 'category-section' }, [
        $h->tag('h1', { class => 'category-title' }, $category_data->{category}),
        $h->tag('div', { class => 'sitelink-list' }, \@articles_html)
    ]);

}

sub link_create {
    # Generate HTML for a site link with favicon and optional alternate links
    # article: {
    #   url => "https://example.com",
    #   name => "Example Site",
    #   althypers => [
    #     { alturl => "...", altname => "..." },
    #     ...
    #   ]
    # }
    # media_path: directory path for favicon files

    my ($h, $article, $media_path) = @_;

    my $domain = '';
    if ($article->{url} =~ m|^https?://([^/]+)|) {
        $domain = $1;
    }

    my $favicon_path = "$media_path/$domain.ico";
    my $favicon_size = $config{'favicon-size'} || 32;

    my $sitelink = $h->tag('a', {
        href => $article->{url},
        class => 'sitelink',
        target => '_blank',
        rel => 'noopener noreferrer'
    }, [
        $h->tag('img', {
            src => $favicon_path,
            alt => $article->{name},
            class => 'sitelink-image',
            width => $favicon_size,
            height => $favicon_size
        }),
        $h->tag('span', { class => 'sitelink-name' }, $article->{name})
    ]);

    my @alt_links;
    if ($article->{althypers} && @{$article->{althypers}}) {
        foreach my $alt (@{$article->{althypers}}) {
            push @alt_links, $h->tag('a', {
                href => $alt->{alturl},
                class => 'alt-link',
                target => '_blank',
                rel => 'noopener noreferrer',
                title => $alt->{altname}
            }, $alt->{altname});
        }
    }

    if (@alt_links) {
        return $h->tag('div', { class => 'sitelink-group' }, [
            $sitelink,
            $h->tag('div', { class => 'alt-links' }, \@alt_links)
        ]);
    } else {
        return $sitelink;
    }
}

sub favicon_coroutine {
    # Handle favicon downloading for all domains
    # portal_list: array reference of categories and articles
    # media_path: directory to save favicons
    # provider: preferred favicon source ('direct', 'google', or 'duckduckgo')

    my ($portal_list_ref, $media_path, $provider) = @_;
    # Implementation to be added

    unless (-d $media_path) {
        print "Creating media directory: $media_path\n";
        mkdir $media_path or die "Cannot create media directory: $!\n";
    }

    my %allowed_providers = (
    "direct" => 1,
    "google" => 1,
    "duckduckgo" => 1,
    );

    unless (exists $allowed_providers{$provider}) {
        die "Unsupported favicon provider: '$provider'. Supported: direct, google, duckduckgo\n";
    }

    print("Starting Favicon Downloads");

    my %domains;

    foreach my $category (@{$portal_list_ref}) {
        foreach my $article (@{$category->{articles}}) {
            # Extract domain from main URL
            if ($article->{url} && $article->{url} =~ m|^https?://([^/]+)|) {
                my $domain = $1;
                $domains{$domain} = {
                    domain => $domain,
                    article_name => $article->{name},
                    type => 'primary'
                };
            }
        }
    }

    print("Found " . scalar(keys %domains) . " unique domains\n");
    my $downloaded = 0;
    my $skipped = 0;
    my $failed = 0;

    foreach my $domain_key (sort keys %domains) {
        my $domain_info = $domains{$domain_key};
        my $favicon_file = path($media_path, "$domain_info->{domain}.ico");

        if ($favicon_file->exists) {
            print "$domain_info->{domain} (exists)\n";
            $skipped++;
            next;
        }
        my $success = favicon_provider_handler($domain_info->{domain}, $favicon_file, $provider);

        if ($success) {
            print "downloaded\n";
            $downloaded++;
        } else {
            print "failed\n";
            $failed++;
        }
    }

    print "  Downloaded: $downloaded\n";
    print "  Already existed: $skipped\n";
    print "  Failed: $failed\n";

    return;
}

sub favicon_download_direct {
    # Download favicon directly from website
    my ($domain, $favicon_file) = @_;

    my $ua = LWP::UserAgent->new(
        timeout => 10,
        agent => "SXPSG/$SXPSG_VERSION",
        ssl_opts => { verify_hostname => 0 },
    );

    my @favicon_urls = (
        "https://$domain/favicon.ico",
        "https://www.$domain/favicon.ico",
        "http://$domain/favicon.ico",
        "http://www.$domain/favicon.ico",
    );

    my $attempts = 0;
    my $last_error = "";

    foreach my $url (@favicon_urls) {
        $attempts++;
        print "  Direct attempt $attempts: $url\n" if $SXPSG_LOGGING_ENABLED;

        my $response = $ua->get($url);

        if ($response->is_success) {
            my $content = $response->content;
            my $content_length = length($content);

            print "    HTTP Status: " . $response->status_line . "\n" if $SXPSG_LOGGING_ENABLED;
            print "    Content-Length: $content_length bytes\n" if $SXPSG_LOGGING_ENABLED;

            if (is_valid_image_content($content)) {
                print "    Valid image detected\n" if $SXPSG_LOGGING_ENABLED;
                return write_favicon_file($favicon_file, $content, "direct: $url");
            } else {
                print "    Invalid image content (not a recognized image format)\n" if $SXPSG_LOGGING_ENABLED;
                # Check first few bytes for debugging
                my $first_bytes = substr($content, 0, 20);
                print "    First 20 bytes: " . unpack('H*', $first_bytes) . "\n" if $SXPSG_LOGGING_ENABLED && $content_length > 0;
            }
        } else {
            $last_error = "HTTP " . $response->code . ": " . $response->message;
            print "    Failed: $last_error\n" if $SXPSG_LOGGING_ENABLED;

            # Check if it's a redirect
            if ($response->code == 301 || $response->code == 302) {
                my $location = $response->header('Location');
                print "    Redirect to: $location\n" if $SXPSG_LOGGING_ENABLED && $location;
            }
        }

        # Add small delay between attempts
        sleep 1 if $attempts < @favicon_urls;
    }

    print "  All direct attempts failed for $domain\n" if $SXPSG_LOGGING_ENABLED;
    return 0;
}

sub favicon_download_google {
    # Download favicon using Google's favicon service
    my ($domain, $favicon_file) = @_;

    my $ua = LWP::UserAgent->new(
        timeout => 10,
        agent => "SXPSG/$SXPSG_VERSION",
    );

    my $url = "https://www.google.com/s2/favicons?domain=$domain&sz=32";
    print "  Google service: $url\n" if $SXPSG_LOGGING_ENABLED;

    my $response = $ua->get($url);

    if ($response->is_success) {
        my $content = $response->content;
        my $content_length = length($content);

        print "    HTTP Status: " . $response->status_line . "\n" if $SXPSG_LOGGING_ENABLED;
        print "    Content-Length: $content_length bytes\n" if $SXPSG_LOGGING_ENABLED;

        if (is_valid_image_content($content)) {
            print "    Valid image from Google\n" if $SXPSG_LOGGING_ENABLED;
            return write_favicon_file($favicon_file, $content, "Google service");
        } else {
            print "    Invalid image content from Google\n" if $SXPSG_LOGGING_ENABLED;
            if ($content_length > 0) {
                my $first_bytes = substr($content, 0, 20);
                print "    First 20 bytes: " . unpack('H*', $first_bytes) . "\n" if $SXPSG_LOGGING_ENABLED;
            }
        }
    } else {
        print "    Failed: HTTP " . $response->code . ": " . $response->message . "\n" if $SXPSG_LOGGING_ENABLED;
    }

    return 0;
}

sub favicon_download_duckduckgo {
    # Download favicon using DuckDuckGo's favicon service
    my ($domain, $favicon_file) = @_;

    my $ua = LWP::UserAgent->new(
        timeout => 10,
        agent => "SXPSG/$SXPSG_VERSION",
    );

    my $url = "https://icons.duckduckgo.com/ip3/$domain.ico";
    print "  DuckDuckGo service: $url\n" if $SXPSG_LOGGING_ENABLED;

    my $response = $ua->get($url);

    if ($response->is_success) {
        my $content = $response->content;
        my $content_length = length($content);

        print "    HTTP Status: " . $response->status_line . "\n" if $SXPSG_LOGGING_ENABLED;
        print "    Content-Length: $content_length bytes\n" if $SXPSG_LOGGING_ENABLED;

        if (is_valid_image_content($content)) {
            print "    Valid image from DuckDuckGo\n" if $SXPSG_LOGGING_ENABLED;
            return write_favicon_file($favicon_file, $content, "DuckDuckGo service");
        } else {
            print "    Invalid image content from DuckDuckGo\n" if $SXPSG_LOGGING_ENABLED;
            if ($content_length > 0) {
                my $first_bytes = substr($content, 0, 20);
                print "    First 20 bytes: " . unpack('H*', $first_bytes) . "\n" if $SXPSG_LOGGING_ENABLED;
            }
        }
    } else {
        print "    Failed: HTTP " . $response->code . ": " . $response->message . "\n" if $SXPSG_LOGGING_ENABLED;
    }

    return 0;
}

# Also add debugging to the favicon_provider_handler:
sub favicon_provider_handler {
    my ($domain, $favicon_file, $provider) = @_;

    print "  Attempting to download favicon for: $domain\n" if $SXPSG_LOGGING_ENABLED;
    print "  Provider: $provider\n" if $SXPSG_LOGGING_ENABLED;

    my %provider_map = (
        "direct" => \&favicon_download_direct,
        "google" => \&favicon_download_google,
        "duckduckgo" => \&favicon_download_duckduckgo,
    );

    my $success = $provider_map{$provider}->($domain, $favicon_file);

    if (!$success && $FAVICON_FALLBACK_ENABLED) {
        print "  Primary provider failed, trying fallbacks...\n" if $SXPSG_LOGGING_ENABLED;
        my @fallback_order;
        if ($provider eq 'direct') {
            @fallback_order = qw(duckduckgo google);
        } elsif ($provider eq 'google') {
            @fallback_order = qw(direct duckduckgo);
        } else { # duckduckgo
            @fallback_order = qw(direct google);
        }

        foreach my $fallback (@fallback_order) {
            print "  Trying fallback: $fallback...\n" if $SXPSG_LOGGING_ENABLED;
            $success = $provider_map{$fallback}->($domain, $favicon_file);
            if ($success) {
                print "  Fallback $fallback succeeded!\n" if $SXPSG_LOGGING_ENABLED;
                last;
            } else {
                print "  Fallback $fallback failed.\n" if $SXPSG_LOGGING_ENABLED;
            }
        }
    }

    return $success;
}

sub write_favicon_file {
    # Universal favicon writer
    # favicon_file: Path::Tiny object for output file
    # content: binary favicon data
    # source: description of where favicon came from (for logging)

    my ($favicon_file, $content, $source) = @_;

    eval {
        $favicon_file->spew($content);
    };

    if ($@) {
        warn "Failed to write favicon file: $@\n";
        return 0;
    }

    # Verify the file was written and has content
    if ($favicon_file->exists && $favicon_file->stat->size > 0) {
        return 1;
    }

    return 0;
}

sub is_valid_image_content {
    # Check if content appears to be a valid image
    # content: binary data to check

    my ($content) = @_;
    return 0 unless $content;

    # Check for minimum size
    return 0 if length($content) < 20;

    # Check for common image headers
    # ICO: starts with \x00\x00\x01\x00
    # PNG: starts with \x89PNG\r\n\x1a\n
    # JPEG: starts with \xFF\xD8\xFF
    # GIF: starts with GIF87a or GIF89a

    if ($content =~ /^\x00\x00\x01\x00/ ||      # ICO
        $content =~ /^\x89PNG\r\n\x1a\n/ ||     # PNG
        $content =~ /^\xFF\xD8\xFF/ ||          # JPEG
        $content =~ /^GIF8[79]a/ ||             # GIF
        $content =~ /^\x89aPNG/                 # Some PNG variants
    ) {
        return 1;
    }

    # Also accept any content that looks like an icon (basic check)
    if ($content =~ /<svg/ || $content =~ /^\x1a\x00/) {
        return 1;
    }

    return 0;
}

sub escape_html {
    # Escape HTML special characters (do not use on URLs)
    # text: string to escape

    my ($text) = @_;
    return '' unless defined $text;

    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;

    return $text;
}

sub help_message {
    print <<"HELP";
Static XHTML Portal Site Generator ver.$SXPSG_VERSION

Usage: ./sxpsg2.perl [options] OR perl sxpsg2.perl [options]

Options:
  --help, -h                Display this help message
  --config-file, -c FILE    Configuration file (default: portal_config.json)
  --list-file, -l FILE      Portal list file (default: portal_list.json)
  --media-dir, -m DIR       Media directory (default: media)
  --config-dir, -d DIR      Configuration directory (default: configuration)
  --template-dir, -t DIR    Template directory (default: template)
  --output-file, -o FILE    Output HTML file (default: portal.html)
  --favicon-provider, -f PROVIDER  Favicon provider: direct, google, duckduckgo
  --no-fallback             Disable favicon provider fallback

Directory Structure:
  media/        - Downloaded favicon files
  template/     - HTML template files
  configuration/- Configuration files

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
HELP
}

sub enviroment_validity {
    my $config_dir = $sxpsg_dirs{c};
    unless (defined $config_dir && $config_dir ne '') {
        die "Configuration directory is not set or empty.\n";
    }

    unless (-d $config_dir) {
        die "No configuration folder was found at '$config_dir'\n";
    }

    unless (defined $config_normative && $config_normative ne '') {
        die "Configuration file name is not set or empty.\n";
    }

    my $config_path = path($config_dir, $config_normative);
    unless ($config_path->exists) {
        die "Configuration file '$config_path' not found.\n";
    }
    print("Using: $config_path");

    unless (defined $portal_list_normative && $portal_list_normative ne '') {
        die "Portal list file name is not set or empty.\n";
    }

    my $list_path = path($config_dir, $portal_list_normative);
    unless ($list_path->exists) {
        die "Portal list file '$list_path' not found.\n";
    }

    print("Using: $list_path");

    my $json_config_text = $config_path->slurp_utf8;
    my $config_data = decode_json($json_config_text);

    my $json_list_text = $list_path->slurp_utf8;
    my $list_data = decode_json($json_list_text);

    %config = process_configuration($config_data);
    %portal_list = process_lists($list_data);

    return 1;
}

sub process_configuration{
  my ($config_data) = @_;
  my %allowed_config_versions = (
#         1 => \&config_version_v1,  # Original bash script format
        4 => \&config_version_v4,  # Current Perl format
    );

  my $version = $config_data->{version} || -1;

  unless (exists $allowed_config_versions{$version}) {
    die "Unsupported configuration version: '$version'. Supported: 4\n";
  }

  return $allowed_config_versions{$version}->($config_data);
}

sub process_lists {
    my ($list_data) = @_;

    my %allowed_list_versions = (
#         1 => \&portal_list_version_v1,  # Original bash script format
        3 => \&portal_list_version_v3,  # Current Perl format
    );

    my $version = $list_data->{version} || -1;

    unless (exists $allowed_list_versions{$version}) {
        die "Unsupported portal list version: '$version'. Supported: 1, 3\n";
    }

    return $allowed_list_versions{$version}->($list_data);
}


sub config_version_v4 {
    # Current v4 configuration format - minimal processing needed
    my ($config_data) = @_;

    # Set defaults for any missing v4 fields
    my %defaults = (
        'title' => 'Portal',
        'media-path' => 'media',
        'template-path' => 'template',
        'template' => 'standard_template.htm',
        'html-version' => 5,
        'output-file' => 'portal.html',
        'favicon-size' => 32,
        'favicon-provider' => 'direct',
        'primary-color' => '#007bff',
        'secondary-color' => '#6c757d',
        'text-primary' => '#333',
        'text-secondary' => '#666',
        'bg-primary' => '#ffffff',
        'bg-secondary' => '#f8f9fa',
        'border-color' => 'transparent',
        'scrollbar-color' => '#888',
    );

    # Merge config data with defaults
    my %processed_config = %defaults;
    foreach my $key (keys %$config_data) {
        $processed_config{$key} = $config_data->{$key} if defined $config_data->{$key};
    }

    return %processed_config;
}

sub portal_list_version_v3 {
    my ($list_data) = @_;

    if ($list_data->{list}) {
        foreach my $category (@{$list_data->{list}}) {
            next unless $category->{articles};

            foreach my $article (@{$category->{articles}}) {
                $article->{name} ||= 'Unnamed Site';
                $article->{althypers} ||= [];
            }
        }
    }

    return %$list_data;
}

sub cli {
    my %options;

    GetOptions(
        'help|h' => \$options{help},
        'config-file|c=s' => \$options{config_file},
        'list-file|l=s' => \$options{list_file},
        'media-dir|m=s' => \$options{media_dir},
        'config-dir|d=s' => \$options{config_dir},
        'template-dir|t=s' => \$options{template_dir},
        'output-file|o=s' => \$options{output_file},
        'favicon-provider|f=s' => \$options{favicon_provider},
        'no-fallback' => \$options{no_fallback},
#         'logging|L' => \$options{logging},
    );

    if ($options{help}) {
        help_message();
        exit 0;
    }

    $config_normative = $options{config_file} if $options{config_file};
    $portal_list_normative = $options{list_file} if $options{list_file};
    $media_folder = $options{media_dir} if $options{media_dir};
    $configuration_folder = $options{config_dir} if $options{config_dir};
    $template_folder = $options{template_dir} if $options{template_dir};

    %sxpsg_dirs = (
        'm' => $media_folder,
        'c' => $configuration_folder,
        't' => $template_folder,
    );
$FAVICON_FALLBACK_ENABLED = 0 if $options{no_fallback};  $SXPSG_LOGGING_ENABLED = 1 if $options{logging};
    main();
}

unless (caller) {
    cli();
}

1;
