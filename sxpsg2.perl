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

#
# Optional encryption dependencies (only required when --encrypt is used):
#   CryptX  ->  dnf install perl-CryptX  OR  cpan CryptX
#   Encode  ->  usually core, but listed for clarity
#

our $SXPSG_VERSION = '2.3250.0perl';

our $config_normative       = 'portal_config.json';
our $portal_list_normative  = 'portal_list.json';
our $hash_implentation_file;
our $hash_key;
our $encrypt_mode = 0;          # --encrypt flag
our %config;
our %portal_list;

our $SXPSG_LOGGING_ENABLED   = 0;
our $FAVICON_FALLBACK_ENABLED = 1;
our $media_folder         = 'media';
our $configuration_folder = 'configuration';
our $template_folder      = 'template';

our %sxpsg_dirs;

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Page creation — orchestrator
# ---------------------------------------------------------------------------

sub page_create {
    favicon_coroutine($portal_list{list}, $config{'media-path'}, $config{'favicon-provider'});

    my @sections_html;
    my $media_path = $config{'media-path'} || 'media';

    foreach my $category (@{$portal_list{list}}) {
        push @sections_html, section_create($category, $media_path);
    }

    # In encrypt mode we keep __SECTIONS__ empty — the real HTML lives
    # inside the ciphertext and gets injected by the JS at runtime.
    my $sections_output = ($encrypt_mode && defined $hash_implentation_file && defined $hash_key)
        ? '<div id="sxpsg-content"></div>'
        : join("\n", @sections_html);

    my %replacements = (
        '__TITLE__'           => $config{'title'}          || 'Portal',
        '__FAVICON_SIZE__'    => $config{'favicon-size'}   || 32,
        '__PRIMARY_COLOUR__'  => $config{'primary-color'}  || '#007bff',
        '__SECONDARY_COLOUR__'=> $config{'secondary-color'}|| '#6c757d',
        '__TEXT_PRIMARY__'    => $config{'text-primary'}   || '#333',
        '__TEXT_SECONDARY__'  => $config{'text-secondary'} || '#666',
        '__BG_PRIMARY__'      => $config{'bg-primary'}     || '#ffffff',
        '__BG_SECONDARY__'    => $config{'bg-secondary'}   || '#f8f9fa',
        '__BORDER_COLOUR__'   => $config{'border-color'}   || '#eee',
        '__SCROLLBAR_COLOUR__'=> $config{'scrollbar-color'}|| '#888',
        '__SECTIONS__'        => $sections_output,
    );

    my $template_file = path($config{'template-path'} || 'template',
                             $config{'template'}      || 'standard_template.htm');
    my $template_content = $template_file->slurp_utf8;

    foreach my $key (keys %replacements) {
        $template_content =~ s/\Q$key\E/$replacements{$key}/g;
    }

    # ------------------------------------------------------------------
    # Hash / Encrypt branching
    # ------------------------------------------------------------------

    if (defined $hash_implentation_file && defined $hash_key) {
        if ($encrypt_mode) {
            page_create_encrypted(\$template_content, \@sections_html);
        } else {
            page_create_hash_insert(\$template_content);
        }
    } else {
        # No hash flags provided — strip placeholder cleanly
        $template_content =~ s/(?:<!--)?__HASHED_PAGE_INSERT__(?:-->)?//g;
    }

    # ------------------------------------------------------------------

    my $output_path = path($config{'output-file'} || 'portal.html');
    $output_path->spew_utf8($template_content);

    print("Generated: $output_path\n");
    return;
}

# ---------------------------------------------------------------------------
# Hash insert — original behaviour
# JS file has __HASH_KEY_LOCALE__ replaced with the literal key string.
# ---------------------------------------------------------------------------

sub page_create_hash_insert {
    my ($template_ref) = @_;

    print("Inserting Hash Implementation (hash-check mode)\n");

    my $js_content = path($hash_implentation_file)->slurp_utf8;
    $js_content =~ s/__HASH_KEY_LOCALE__/$hash_key/g;

    $$template_ref =~ s/(?:<!--)?__HASHED_PAGE_INSERT__(?:-->)?/<script>\n$js_content\n<\/script>/;
}

# ---------------------------------------------------------------------------
# Encrypted page — new behaviour
# Sections are AES-256-GCM encrypted at build time with a PBKDF2-derived key.
# The JS file receives __ENCRYPTED_PAYLOAD__ (base64 ciphertext blob).
# __HASH_KEY_LOCALE__ is NOT used here — the passphrase comes from the URL
# fragment at runtime and never touches the HTML source.
#
# Payload layout (binary, then base64-encoded):
#   [ salt 16B ][ iv 12B ][ tag 16B ][ ciphertext ]
#
# Requires CryptX:  dnf install perl-CryptX  OR  cpan CryptX
# ---------------------------------------------------------------------------

sub page_create_encrypted {
    my ($template_ref, $sections_ref) = @_;

    # Lazy-load encryption modules so non-encrypt builds need no CryptX
    eval {
        require Crypt::AuthEnc::GCM;
        require Crypt::KeyDerivation;
        require Crypt::Misc;
        require MIME::Base64;
        require Encode;
        Encode->import('encode');
    };
    if ($@) {
        die "Encryption requires the CryptX module.\n"
          . "Install with:  dnf install perl-CryptX  OR  cpan CryptX\n"
          . "Original error: $@\n";
    }

    print("Inserting Hash Implementation (encrypt mode)\n");

    my $sections_content = join("\n", @$sections_ref);
    my $plaintext        = Encode::encode('UTF-8', $sections_content);

    # Random salt and IV
    my $salt = Crypt::Misc::random_bytes(16);
    my $iv   = Crypt::Misc::random_bytes(12);

    # Derive 256-bit key from passphrase using PBKDF2-SHA256
    my $key = Crypt::KeyDerivation::pbkdf2($hash_key, $salt, 100_000, 'SHA256', 32);

    # AES-256-GCM encrypt
    my ($ciphertext, $tag) = Crypt::AuthEnc::GCM::gcm_encrypt_authenticate(
        'AES', $key, $iv, '', $plaintext
    );

    # Pack and base64-encode the payload
    my $payload = MIME::Base64::encode_base64($salt . $iv . $tag . $ciphertext, '');

    # Inject into JS file — only __ENCRYPTED_PAYLOAD__ is substituted here.
    # __HASH_KEY_LOCALE__ is intentionally left alone (not used in encrypt mode).
    my $js_content = path($hash_implentation_file)->slurp_utf8;
    $js_content =~ s/__ENCRYPTED_PAYLOAD__/$payload/g;

    $$template_ref =~ s/(?:<!--)?__HASHED_PAGE_INSERT__(?:-->)?/<script>\n$js_content\n<\/script>/;
}

# ---------------------------------------------------------------------------
# Section / link builders (unchanged)
# ---------------------------------------------------------------------------

sub section_create {
    my ($category_data, $media_path) = @_;

    my $h = HTML::Tiny->new;
    my @articles_html;

    if ($category_data->{articles} && @{$category_data->{articles}}) {
        foreach my $article (@{$category_data->{articles}}) {
            push @articles_html, link_create($h, $article, $media_path);
        }
    }

    return $h->tag('section', { class => 'category-section' }, [
        $h->tag('h1',  { class => 'category-title' }, $category_data->{category}),
        $h->tag('div', { class => 'sitelink-list'  }, \@articles_html)
    ]);
}

sub link_create {
    my ($h, $article, $media_path) = @_;

    my $domain = '';
    if ($article->{url} =~ m|^https?://([^/]+)|) {
        $domain = $1;
    }

    my $favicon_path = "$media_path/$domain.ico";
    my $favicon_size = $config{'favicon-size'} || 32;

    my $sitelink = $h->tag('a', {
        href   => $article->{url},
        class  => 'sitelink',
        target => '_blank',
        rel    => 'noopener noreferrer'
    }, [
        $h->tag('img', {
            src    => $favicon_path,
            alt    => $article->{name},
            class  => 'sitelink-image',
            width  => $favicon_size,
            height => $favicon_size
        }),
        $h->tag('span', { class => 'sitelink-name' }, $article->{name})
    ]);

    my @alt_links;
    if ($article->{althypers} && @{$article->{althypers}}) {
        foreach my $alt (@{$article->{althypers}}) {
            push @alt_links, $h->tag('a', {
                href   => $alt->{alturl},
                class  => 'alt-link',
                target => '_blank',
                rel    => 'noopener noreferrer',
                title  => $alt->{altname}
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

# ---------------------------------------------------------------------------
# Favicon handling (unchanged)
# ---------------------------------------------------------------------------

sub favicon_coroutine {
    my ($portal_list_ref, $media_path, $provider) = @_;

    unless (-d $media_path) {
        print "Creating media directory: $media_path\n";
        mkdir $media_path or die "Cannot create media directory: $!\n";
    }

    my %allowed_providers = (
        "direct"    => 1,
        "google"    => 1,
        "duckduckgo"=> 1,
    );

    unless (exists $allowed_providers{$provider}) {
        die "Unsupported favicon provider: '$provider'. Supported: direct, google, duckduckgo\n";
    }

    print("Starting Favicon Downloads");

    my %domains;
    foreach my $category (@{$portal_list_ref}) {
        foreach my $article (@{$category->{articles}}) {
            if ($article->{url} && $article->{url} =~ m|^https?://([^/]+)|) {
                my $domain = $1;
                $domains{$domain} = {
                    domain       => $domain,
                    article_name => $article->{name},
                    type         => 'primary'
                };
            }
        }
    }

    print("Found " . scalar(keys %domains) . " unique domains\n");
    my ($downloaded, $skipped, $failed) = (0, 0, 0);

    foreach my $domain_key (sort keys %domains) {
        my $domain_info  = $domains{$domain_key};
        my $favicon_file = path($media_path, "$domain_info->{domain}.ico");

        if ($favicon_file->exists) {
            print "$domain_info->{domain} (exists)\n";
            $skipped++;
            next;
        }
        my $success = favicon_provider_handler($domain_info->{domain}, $favicon_file, $provider);

        if ($success) { print "downloaded\n"; $downloaded++; }
        else          { print "failed\n";     $failed++;     }
    }

    print "  Downloaded: $downloaded\n";
    print "  Already existed: $skipped\n";
    print "  Failed: $failed\n";

    return;
}

sub favicon_download_direct {
    my ($domain, $favicon_file) = @_;

    my $ua = LWP::UserAgent->new(
        timeout  => 10,
        agent    => "SXPSG/$SXPSG_VERSION",
        ssl_opts => { verify_hostname => 0 },
    );

    my @favicon_urls = (
        "https://$domain/favicon.ico",
        "https://www.$domain/favicon.ico",
        "http://$domain/favicon.ico",
        "http://www.$domain/favicon.ico",
    );

    my $attempts   = 0;
    my $last_error = "";

    foreach my $url (@favicon_urls) {
        $attempts++;
        print "  Direct attempt $attempts: $url\n" if $SXPSG_LOGGING_ENABLED;

        my $response = $ua->get($url);

        if ($response->is_success) {
            my $content        = $response->content;
            my $content_length = length($content);

            print "    HTTP Status: "     . $response->status_line . "\n" if $SXPSG_LOGGING_ENABLED;
            print "    Content-Length: $content_length bytes\n"           if $SXPSG_LOGGING_ENABLED;

            if (is_valid_image_content($content)) {
                print "    Valid image detected\n" if $SXPSG_LOGGING_ENABLED;
                return write_favicon_file($favicon_file, $content, "direct: $url");
            } else {
                print "    Invalid image content\n" if $SXPSG_LOGGING_ENABLED;
                if ($SXPSG_LOGGING_ENABLED && $content_length > 0) {
                    my $first_bytes = substr($content, 0, 20);
                    print "    First 20 bytes: " . unpack('H*', $first_bytes) . "\n";
                }
            }
        } else {
            $last_error = "HTTP " . $response->code . ": " . $response->message;
            print "    Failed: $last_error\n" if $SXPSG_LOGGING_ENABLED;
            if ($SXPSG_LOGGING_ENABLED && ($response->code == 301 || $response->code == 302)) {
                my $location = $response->header('Location');
                print "    Redirect to: $location\n" if $location;
            }
        }

        sleep 1 if $attempts < @favicon_urls;
    }

    print "  All direct attempts failed for $domain\n" if $SXPSG_LOGGING_ENABLED;
    return 0;
}

sub favicon_download_google {
    my ($domain, $favicon_file) = @_;

    my $ua  = LWP::UserAgent->new(timeout => 10, agent => "SXPSG/$SXPSG_VERSION");
    my $url = "https://www.google.com/s2/favicons?domain=$domain&sz=32";
    print "  Google service: $url\n" if $SXPSG_LOGGING_ENABLED;

    my $response = $ua->get($url);

    if ($response->is_success) {
        my $content = $response->content;
        print "    HTTP Status: " . $response->status_line . "\n" if $SXPSG_LOGGING_ENABLED;
        print "    Content-Length: " . length($content) . " bytes\n" if $SXPSG_LOGGING_ENABLED;

        if (is_valid_image_content($content)) {
            print "    Valid image from Google\n" if $SXPSG_LOGGING_ENABLED;
            return write_favicon_file($favicon_file, $content, "Google service");
        }
        print "    Invalid image content from Google\n" if $SXPSG_LOGGING_ENABLED;
    } else {
        print "    Failed: HTTP " . $response->code . ": " . $response->message . "\n"
            if $SXPSG_LOGGING_ENABLED;
    }

    return 0;
}

sub favicon_download_duckduckgo {
    my ($domain, $favicon_file) = @_;

    my $ua  = LWP::UserAgent->new(timeout => 10, agent => "SXPSG/$SXPSG_VERSION");
    my $url = "https://icons.duckduckgo.com/ip3/$domain.ico";
    print "  DuckDuckGo service: $url\n" if $SXPSG_LOGGING_ENABLED;

    my $response = $ua->get($url);

    if ($response->is_success) {
        my $content = $response->content;
        print "    HTTP Status: " . $response->status_line . "\n" if $SXPSG_LOGGING_ENABLED;
        print "    Content-Length: " . length($content) . " bytes\n" if $SXPSG_LOGGING_ENABLED;

        if (is_valid_image_content($content)) {
            print "    Valid image from DuckDuckGo\n" if $SXPSG_LOGGING_ENABLED;
            return write_favicon_file($favicon_file, $content, "DuckDuckGo service");
        }
        print "    Invalid image content from DuckDuckGo\n" if $SXPSG_LOGGING_ENABLED;
    } else {
        print "    Failed: HTTP " . $response->code . ": " . $response->message . "\n"
            if $SXPSG_LOGGING_ENABLED;
    }

    return 0;
}

sub favicon_provider_handler {
    my ($domain, $favicon_file, $provider) = @_;

    print "  Attempting: $domain  provider: $provider\n" if $SXPSG_LOGGING_ENABLED;

    my %provider_map = (
        "direct"     => \&favicon_download_direct,
        "google"     => \&favicon_download_google,
        "duckduckgo" => \&favicon_download_duckduckgo,
    );

    my $success = $provider_map{$provider}->($domain, $favicon_file);

    if (!$success && $FAVICON_FALLBACK_ENABLED) {
        print "  Primary provider failed, trying fallbacks...\n" if $SXPSG_LOGGING_ENABLED;
        my @fallback_order;
        if    ($provider eq 'direct')     { @fallback_order = qw(duckduckgo google); }
        elsif ($provider eq 'google')     { @fallback_order = qw(direct duckduckgo); }
        else                              { @fallback_order = qw(direct google);      }

        foreach my $fallback (@fallback_order) {
            print "  Trying fallback: $fallback...\n" if $SXPSG_LOGGING_ENABLED;
            $success = $provider_map{$fallback}->($domain, $favicon_file);
            if ($success) {
                print "  Fallback $fallback succeeded!\n" if $SXPSG_LOGGING_ENABLED;
                last;
            }
            print "  Fallback $fallback failed.\n" if $SXPSG_LOGGING_ENABLED;
        }
    }

    return $success;
}

sub write_favicon_file {
    my ($favicon_file, $content, $source) = @_;

    eval { $favicon_file->spew($content); };
    if ($@) {
        warn "Failed to write favicon file: $@\n";
        return 0;
    }
    return ($favicon_file->exists && $favicon_file->stat->size > 0) ? 1 : 0;
}

sub is_valid_image_content {
    my ($content) = @_;
    return 0 unless $content && length($content) >= 20;

    return 1 if $content =~ /^\x00\x00\x01\x00/;   # ICO
    return 1 if $content =~ /^\x89PNG\r\n\x1a\n/;  # PNG
    return 1 if $content =~ /^\xFF\xD8\xFF/;        # JPEG
    return 1 if $content =~ /^GIF8[79]a/;           # GIF
    return 1 if $content =~ /^\x89aPNG/;            # PNG variant
    return 1 if $content =~ /<svg/;                 # SVG
    return 1 if $content =~ /^\x1a\x00/;            # legacy ICO
    return 0;
}

# ---------------------------------------------------------------------------
# Misc helpers (unchanged)
# ---------------------------------------------------------------------------

sub escape_html {
    my ($text) = @_;
    return '' unless defined $text;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;
    return $text;
}

# ---------------------------------------------------------------------------
# Environment validation (unchanged)
# ---------------------------------------------------------------------------

sub enviroment_validity {
    my $config_dir = $sxpsg_dirs{c};
    die "Configuration directory is not set or empty.\n"
        unless (defined $config_dir && $config_dir ne '');
    die "No configuration folder was found at '$config_dir'\n"
        unless -d $config_dir;
    die "Configuration file name is not set or empty.\n"
        unless (defined $config_normative && $config_normative ne '');

    my $config_path = path($config_dir, $config_normative);
    die "Configuration file '$config_path' not found.\n"
        unless $config_path->exists;
    print("Using: $config_path");

    die "Portal list file name is not set or empty.\n"
        unless (defined $portal_list_normative && $portal_list_normative ne '');

    my $list_path = path($config_dir, $portal_list_normative);
    die "Portal list file '$list_path' not found.\n"
        unless $list_path->exists;
    print("Using: $list_path");

    %config      = process_configuration(decode_json($config_path->slurp_utf8));
    %portal_list = process_lists(decode_json($list_path->slurp_utf8));

    return 1;
}

sub process_configuration {
    my ($config_data) = @_;
    my %allowed = (4 => \&config_version_v4);
    my $version  = $config_data->{version} || -1;
    die "Unsupported configuration version: '$version'. Supported: 4\n"
        unless exists $allowed{$version};
    return $allowed{$version}->($config_data);
}

sub process_lists {
    my ($list_data) = @_;
    my %allowed = (3 => \&portal_list_version_v3);
    my $version  = $list_data->{version} || -1;
    die "Unsupported portal list version: '$version'. Supported: 3\n"
        unless exists $allowed{$version};
    return $allowed{$version}->($list_data);
}

sub config_version_v4 {
    my ($config_data) = @_;
    my %defaults = (
        'title'          => 'Portal',
        'media-path'     => 'media',
        'template-path'  => 'template',
        'template'       => 'standard_template.htm',
        'html-version'   => 5,
        'output-file'    => 'portal.html',
        'favicon-size'   => 32,
        'favicon-provider'=> 'direct',
        'primary-color'  => '#007bff',
        'secondary-color'=> '#6c757d',
        'text-primary'   => '#333',
        'text-secondary' => '#666',
        'bg-primary'     => '#ffffff',
        'bg-secondary'   => '#f8f9fa',
        'border-color'   => 'transparent',
        'scrollbar-color'=> '#888',
    );
    my %out = %defaults;
    foreach my $key (keys %$config_data) {
        $out{$key} = $config_data->{$key} if defined $config_data->{$key};
    }
    return %out;
}

sub portal_list_version_v3 {
    my ($list_data) = @_;
    if ($list_data->{list}) {
        foreach my $category (@{$list_data->{list}}) {
            next unless $category->{articles};
            foreach my $article (@{$category->{articles}}) {
                $article->{name}      ||= 'Unnamed Site';
                $article->{althypers} ||= [];
            }
        }
    }
    return %$list_data;
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

sub help_message {
    print <<"HELP";
Static XHTML Portal Site Generator ver.$SXPSG_VERSION

Usage: ./sxpsg2.perl [options] OR perl sxpsg2.perl [options]

Options:
  --help, -h                       Display this help message
  --config-file, -c FILE.json      Configuration file (default: portal_config.json)
  --list-file, -l FILE.json        Portal list file (default: portal_list.json)
  --media-dir, -m DIR              Media directory (default: media)
  --config-dir, -d DIR             Configuration directory (default: configuration)
  --template-dir, -t DIR           Template directory (default: template)
  --output-file, -o FILENAME       Output HTML file (default: portal.html)
  --favicon-provider, -f PROVIDER  Favicon provider: 'direct | google | duckduckgo'
  --no-fallback                    Disable favicon provider fallback
  --include-hash, -j FILE.js       Insert __HASHED_PAGE_INSERT__ from a *.js file
                                       (wrapped in <script> tags)
  --hash-key, -k STRING            Passphrase / key for hash implementation
                                       (__HASH_KEY_LOCALE__ inside the .js file)
  --hash-file, -n FILE             Load passphrase from file (overrides --hash-key)
  --encrypt, -e                    Encrypt page sections with AES-256-GCM at build
                                       time. Requires --include-hash and --hash-key /
                                       --hash-file. Requires CryptX module.
                                       JS placeholder: __ENCRYPTED_PAYLOAD__
                                       (NOT __HASH_KEY_LOCALE__ — key stays off disk)

Modes:
  No hash flags          Plain static HTML, no protection.
  --include-hash -j -k   Hash-check only: JS hides page if fragment doesn't match.
                           Sections are in plain source. __HASH_KEY_LOCALE__ replaced.
  --include-hash -j -k   AES-256-GCM: sections encrypted at build time, decrypted
    --encrypt              in browser via URL fragment. Source contains only ciphertext.
                           __ENCRYPTED_PAYLOAD__ replaced. __HASH_KEY_LOCALE__ unused.

Fill Tags:
  See TAGS.txt for full list and placement notes.

Directory Structure:
  media/         Downloaded favicon files
  template/      HTML template files
  scripts/       JS insert files
  configuration/ Configuration JSON files

HELP
}

sub cli {
    my %options;

    GetOptions(
        'help|h'              => \$options{help},
        'config-file|c=s'     => \$options{config_file},
        'list-file|l=s'       => \$options{list_file},
        'media-dir|m=s'       => \$options{media_dir},
        'config-dir|d=s'      => \$options{config_dir},
        'template-dir|t=s'    => \$options{template_dir},
        'output-file|o=s'     => \$options{output_file},
        'favicon-provider|f=s'=> \$options{favicon_provider},
        'no-fallback'         => \$options{no_fallback},
        # Hash / encrypt
        'include-hash|j=s'    => \$options{hash_implentation_file},
        'hash-key|k=s'        => \$options{hash_key},
        'hash-file|n=s'       => \$options{hash_file},
        'encrypt|e'           => \$options{encrypt},
    );

    if ($options{help}) {
        help_message();
        exit 0;
    }

    # hash-file overrides hash-key
    if (defined $options{hash_file}) {
        $options{hash_key} = path($options{hash_file})->slurp_utf8;
        chomp $options{hash_key};
    }

    # Validate encrypt requires the other two flags
    if ($options{encrypt} && !(defined $options{hash_implentation_file} && defined $options{hash_key})) {
        die "--encrypt requires both --include-hash (-j) and a key via --hash-key (-k) or --hash-file (-n)\n";
    }

    $config_normative      = $options{config_file}   if $options{config_file};
    $portal_list_normative = $options{list_file}      if $options{list_file};
    $media_folder          = $options{media_dir}      if $options{media_dir};
    $configuration_folder  = $options{config_dir}     if $options{config_dir};
    $template_folder       = $options{template_dir}   if $options{template_dir};

    $hash_implentation_file = $options{hash_implentation_file} if $options{hash_implentation_file};
    $hash_key               = $options{hash_key}               if $options{hash_key};
    $encrypt_mode           = 1                                if $options{encrypt};

    $FAVICON_FALLBACK_ENABLED = 0 if $options{no_fallback};

    %sxpsg_dirs = (
        'm' => $media_folder,
        'c' => $configuration_folder,
        't' => $template_folder,
    );

    main();
}

unless (caller) {
    cli();
}

1;
