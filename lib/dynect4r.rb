require 'rubygems'
require 'json'
require 'logger'
require 'rest_client'

module Dynect

  class Client

    # log in, set auth token
    def initialize(params)
      @base_url = 'https://api2.dynect.net'
      @headers = { :content_type => :json, :accept => :json }
      response = rest_call(:post, 'Session', params)
      @headers['Auth-Token'] = response['data']['token']
    end

    # do a rest call
    def rest_call(action, resource, arguments = nil)

      # set up retry loop
      max_tries = 12
      for try_counter in (1..max_tries)

        # pause between retries
        if try_counter > 1
          sleep(5)
        end

        resource_url = resource_to_url(resource)

        # do rest call
        begin
          response = case action
          when :post, :put
            RestClient.send(action, resource_url, arguments.to_json, @headers) do |res,req|
              Dynect::Response.new(res)
            end
          else
            RestClient.send(action, resource_url, @headers) do |res,req|
              Dynect::Response.new(res)
            end
          end

          # if we got this far, then it's safe to break out of the retry loop
          break

        # on redirect, rewrite rest call params and retry
        rescue RedirectError
          if try_counter < max_tries
            action = :get
            resource = $!.message
            arguments = nil
          else
            raise OperationTimedOut, "Maximum number of tries (%d) exceeded on resource: %s" % [max_tries, resource]
          end
        end

      end

      # return a response object
      response
    end

    private

    # convert the given resource into a proper url
    def resource_to_url(resource)

      # convert into an array
      if resource.is_a? String
        resource = resource.split('/')
      end

      # remove empty elements
      resource.delete('')

      # make sure first element is 'REST'
      if resource[0] != 'REST'
        resource.unshift('REST')
      end

      # prepend base url and convert back to string
      "%s/%s/" % [@base_url, resource.join('/')]
    end

  end

  class Response

    def initialize(response)

      # parse response
      begin
        @hash = JSON.parse(response)
      rescue JSON::ParserError
        if response =~ /REST\/Job\/[0-9]+/
          raise RedirectError, response
        else
         raise
        end
      end

      # raise error based on error code
      if @hash.has_key?('msgs')
        @hash['msgs'].each do |msg|
          case msg['ERR_CD']
          when 'ILLEGAL_OPERATION'
            raise IllegalOperationError, msg['INFO']
          when 'INTERNAL_ERROR'
            raise InternalErrorError, msg['INFO']
          when 'INVALID_DATA'
            raise InvalidDataError, msg['INFO']
          when 'INVALID_REQUEST'
            raise InvalidRequestError, msg['INFO']
          when 'INVALID_VERSION'
            raise InvalidVersionError, msg['INFO']
          when 'MISSING_DATA'
            raise MissingDataError, msg['INFO']
          when 'NOT_FOUND'
            raise NotFoundError, msg['INFO']
          when 'OPERATION_FAILED'
            raise OperationFailedError, msg['INFO']
          when 'PERMISSION_DENIED'
            raise PermissionDeniedError, msg['INFO']
          when 'SERVICE_UNAVAILABLE'
            raise ServiceUnavailableError, msg['INFO']
          when 'TARGET_EXISTS'
            raise TargetExistsError, msg['INFO']
          when 'UNKNOWN_ERROR'
            raise UnknownErrorError, msg['INFO']
          end
        end
      end
    end

    def [](key)
      @hash[key]
    end

  end

  # exceptions generated by class
  class DynectError < StandardError; end
  class RedirectError < DynectError; end
  class OperationTimedOut < DynectError; end

    # exceptions generated by api
  class IllegalOperationError < DynectError; end
  class InternalErrorError < DynectError; end
  class InvalidDataError < DynectError; end
  class InvalidRequestError < DynectError; end
  class InvalidVersionError < DynectError; end
  class MissingDataError < DynectError; end
  class NotFoundError < DynectError; end
  class OperationFailedError < DynectError; end
  class PermissionDeniedError < DynectError; end
  class ServiceUnavailableError < DynectError; end
  class TargetExistsError < DynectError; end
  class UnknownErrorError < DynectError; end

  class Logger < Logger

    # override << operator to control rest_client logging
    # see http://github.com/archiloque/rest-client/issues/issue/34/
    def << (msg)
      debug(msg.strip)
    end
  end

  class << self

    # return the appropriate rest resource for the given rtype
    def rtype_to_resource(rtype)
      rtype.upcase + 'Record'
    end

    # return a hash of arguments for the specified rtype
    def args_for_rtype(rtype, rdata)

      arg_array = case rtype
      when 'A', 'AAAA'
        ['address']
      when 'CNAME'
        ['cname']
      when 'DNSKEY', 'KEY'
        ['flags', 'protocol', 'algorithm', 'public_key']
      when 'DS'
        ['keytag', 'algorithm', 'digtype', 'digest']
      when 'LOC'
        ['version', 'size', 'horiz_pre', 'vert_pre' 'latitude', 'longitude', 'altitude']
      when 'MX'
        ['preference', 'exchange']
      when 'NS'
        ['nsdname']
      when 'PTR'
        ['ptrdname']
      when 'RP'
        ['mbox', 'txtdname']
      when 'SOA'
        ['rname']
      when 'SRV'
        ['priority', 'weight', 'port', 'target']
      when 'TXT'
        ['txtdata']
      else
        []
      end

      if rtype == 'TXT'
        rdata = { arg_array[0] => rdata }
      else
        rdata.split.inject({}) { |memo,obj| memo[arg_array[memo.length]] = obj; memo }
      end
    end

  end

end
