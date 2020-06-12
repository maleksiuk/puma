require 'mkmf'
require 'cgi'

dir_config("puma_http11")

if $mingw && RUBY_VERSION >= '2.4'
  append_cflags  '-fstack-protector-strong -D_FORTIFY_SOURCE=2'
  append_ldflags '-fstack-protector-strong -l:libssp.a'
  have_library 'ssp'
end

if ENV['PUMA_COMPILE_OPTS']
  compile_options = CGI::parse(ENV['PUMA_COMPILE_OPTS'])

  # CGI::parse returns a hash with default [] instead of nil
  if compile_options['querymaxlength'].any?
    query_max_length = compile_options['querymaxlength'].first
    append_cflags "-DCONFIGURED_QUERY_STRING_MAX_LENGTH=#{query_max_length}"
  end
end

unless ENV["DISABLE_SSL"]
  dir_config("openssl")

  if %w'crypto libeay32'.find {|crypto| have_library(crypto, 'BIO_read')} and
      %w'ssl ssleay32'.find {|ssl| have_library(ssl, 'SSL_CTX_new')}

    have_header "openssl/bio.h"

    # below is  yes for 1.0.2 & later
    have_func  "DTLS_method"                  , "openssl/ssl.h"

    # below are yes for 1.1.0 & later, may need to check func rather than macro
    # with versions after 1.1.1
    have_func  "TLS_server_method"            , "openssl/ssl.h"
    have_macro "SSL_CTX_set_min_proto_version", "openssl/ssl.h"
  end
end

create_makefile("puma/puma_http11")
