# frozen_string_literal: true

module Puma
  module MiniSSL
    class Context
      attr_accessor :verify_mode
      attr_reader :no_tlsv1, :no_tlsv1_1

      def initialize
        @no_tlsv1   = false
        @no_tlsv1_1 = false
      end

      attr_reader :key
      attr_reader :cert
      attr_reader :ca
      attr_accessor :ssl_cipher_filter

      def key=(key)
        raise ArgumentError, "No such key file '#{key}'" unless File.exist? key
        @key = key
      end

      def cert=(cert)
        raise ArgumentError, "No such cert file '#{cert}'" unless File.exist? cert
        @cert = cert
      end

      def ca=(ca)
        raise ArgumentError, "No such ca file '#{ca}'" unless File.exist? ca
        @ca = ca
      end

      def check
        raise "Key not configured" unless @key
        raise "Cert not configured" unless @cert
      end

      # disables TLSv1
      # @!attribute [w] no_tlsv1=
      def no_tlsv1=(tlsv1)
        raise ArgumentError, "Invalid value of no_tlsv1=" unless ['true', 'false', true, false].include?(tlsv1)
        @no_tlsv1 = tlsv1
      end

      # disables TLSv1 and TLSv1.1.  Overrides `#no_tlsv1=`
      # @!attribute [w] no_tlsv1_1=
      def no_tlsv1_1=(tlsv1_1)
        raise ArgumentError, "Invalid value of no_tlsv1_1=" unless ['true', 'false', true, false].include?(tlsv1_1)
        @no_tlsv1_1 = tlsv1_1
      end

    end

    VERIFY_NONE = 0
    VERIFY_PEER = 1
    VERIFY_FAIL_IF_NO_PEER_CERT = 2
  end
end
