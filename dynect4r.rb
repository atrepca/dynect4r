#!/usr/bin/ruby -W0
################################################################################
# dynect4r - Ruby library and command line client for Dynect SOAP API
# Copyright (c) 2010 Michael Conigliaro <mike [at] conigliaro [dot] org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
################################################################################

require 'logger'
require 'optparse'
require 'pp'
require 'socket'
require 'rubygems'
require 'savon'

module Dynect

  class Client

    attr_reader :response_hash, :response_messages

    # constructor
    def initialize(customer, username, password)
      wsdl = 'https://api.dynect.net/soap'
      @customer = customer
      @username = username
      @password = password
      @soap_client = soap_client = Savon::Client.new(wsdl)
      @soap_namespaces = {
        'xmlns:wsdl'        => '/DynectAPI/', # FIXME: remove wsdl prefix from all soap calls
        'xmlns:xsi'         => 'http://www.w3.org/2001/XMLSchema-instance',
        'xmlns:soapenc'     => 'http://schemas.xmlsoap.org/soap/encoding/',
        'xmlns:xsd'         => 'http://www.w3.org/2001/XMLSchema',
        'env:encodingStyle' => 'http://schemas.xmlsoap.org/soap/encoding/'
      }
    end

    # do soap call
    def soap_call(method, args = {})

      response = @soap_client.send(method.to_sym) do |soap|

        # set namesaces
        soap.namespaces.merge!(@soap_namespaces)

        # convert method name from lower-camelcase to camelcase
        soap.action[0] = soap.action[0,1].upcase
        soap.input[0] = soap.input[0,1].upcase

        # set common attributes for all SOAP methods
        soap.body = {
          :attributes! => {
            method => { 'xmlns' => '/DynectAPI/' }
          },
          'c-gensym3' => {
            'cust' => @customer,
            'user' => @username,
            'pass' => @password,
          }
        }

        # merge per-method attributes
        soap.body['c-gensym3'].merge!(args)

      end

      # get response hash
      xml_method_response = response.to_hash.keys.first.to_sym
      xml_gensym = nil
      response.to_hash[xml_method_response].keys.each do |key|
        if key.to_s =~ /gensym/
          xml_gensym = key
        end
      end
      @response_hash = response.to_hash[xml_method_response][xml_gensym]

      # save all messages and errors
      response_messages = []
      if @response_hash[:messages]
        @response_hash[:messages].each do |k,v|
          response_messages << "%s: %s" % [k, v]
        end
      end
      if @response_hash[:errors]
        @response_hash[:errors].each do |k,v|
          response_messages << "%s: %s" % [k, v]
        end
      end
      @response_messages = response_messages.join(', ')

      return response
    end

    # return ordered list of parameters for each record type
    def rdata_hash_opts(rtype)
      case rtype
      when 'A', 'AAAA'
        ['address']
      when 'CNAME'
        ['cname']
      when 'KEY'
        ['flags', 'protocol', 'algorithm', 'public_key']
      when 'LOC'
        ['latitude', 'longitude', 'altitude', 'size', 'horiz_pre', 'vert_pre']
      when 'MX'
        ['preference', 'exchange']
      when 'NS'
        ['nsdname']
      when 'PTR'
        ['ptrdname']
      when 'SOA'
        ['mname', 'rname', 'serial', 'refresh', 'retry', 'expire', 'minimum']
      when 'SRV'
        ['priority', 'weight', 'port', 'target']
      when 'TXT'
        ['txtdata']
      else
        []
      end
    end

  end

end

# command line client
if __FILE__ == $0

  # set default command line options
  options = {
    :cred_file => './dynect4r.secret',
    :customer  => nil,
    :username  => nil,
    :password  => nil,
    :zone      => nil,
    :node      => Socket.gethostbyname(Socket.gethostname).first + '.',
    :ttl       => 86400,
    :type      => 'A',
    :rdata     => nil,
    :log_level => 'warn'
  }

  # parse command line options
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] [rdata][, ...]\n" \
      + "Example: #{$0} -n srv.example.org -t SRV 0 10 20 target.example.org"

    opts.on('-c', '--credentials-file VALUE', 'Path to file containing API customer/username/password (default: %s)' % options[:cred_file]) do |opt|
      options[:cred_file] = opt
    end

    opts.on('-z', '--zone VALUE', 'DNS Zone (default: Auto-detect)') do |opt|
      options[:zone] = opt
    end

    opts.on('-n', '--node VALUE', 'Node name (default: %s)' % options[:node]) do |opt|
      options[:node] = opt
    end

    opts.on('-s', '--ttl VALUE', 'Time to Live (default: %s)' % options[:ttl]) do |opt|
      options[:ttl] = opt
    end

    opts.on('-t', '--type VALUE', 'Record type (default: %s)' % options[:type]) do |opt|
      options[:type] = opt.upcase
    end

    opts.on('-v', '--verbosity VALUE', 'Log verbosity (default: %s)' % options[:log_level]) do |opt|
      options[:log_level] = opt
    end

    opts.on('--dry-run', "Perform a trial run without making changes") do |opt|
      options[:dry_run] = opt
    end

  end.parse!

  # instantiate logger
  log = Logger.new(STDOUT)
  Savon::Request.logger = log
  log.level = eval('Logger::' + options[:log_level].upcase)

  # disable savon exceptions so we can access the error descriptions
  Savon::Response.raise_errors = false

  # validate command line options
  begin
    (options[:customer], options[:username], options[:password]) = File.open(options[:cred_file]).readline().strip().split()
  rescue Errno::ENOENT
    log.error('Credentials file does not exist: %s' % options[:cred_file])
    Process.exit(1)
  end
  if !options[:zone]
    options[:zone] = options[:node][(options[:node].index('.') + 1)..-1]
  end
  if ARGV.size > 0
    options[:rdata] = ARGV.join(' ').split(',')
  end

  # instantiate dynect client
  c = Dynect::Client.new(options[:customer], options[:username], options[:password])

  # check if node exists and create if necessary
  if options[:rdata]
    c.soap_call('NodeGet!', {
      'zone' => options[:zone],
      'node' => options[:node]
    })
    if c.response_hash[:status] != 'success'
      if options[:dry_run]
        log.warn('Will create node (Zone="%s" Node="%s")' %
          [options[:zone], options[:node]])
      else
        c.soap_call('NodeAdd!', {
          'zone' => options[:zone],
          'node' => options[:node]
        })
        if c.response_hash[:status] == 'success'
          log.warn('Created node (Zone="%s" Node="%s")' %
            [options[:zone], options[:node]])
        else
          log.error('Failed to create node (Zone="%s" Node="%s") - %s' %
            [options[:zone], options[:node], c.response_messages])
          Process.exit(1)
        end
      end
    end
  end

  # query for existing records
  c.soap_call('RecordGet!', {
    'zone' => options[:zone],
    'node' => options[:node],
    'type' => options[:type]
  })
  if c.response_hash[:status] != 'success'
    log.error('Query for existing records failed - %s' % c.response_messages)
    Process.exit(1)
  else

    # make sure we're always dealing with an array of resource records
    records = []
    if c.response_hash[:records][:item].type == Hash
      records[0] = c.response_hash[:records][:item]
    elsif c.response_hash[:records][:item].type == Array
      records = c.response_hash[:records][:item]
    end

    # loop through existing records
    records.each do |record|

      # delete existing records
      if options[:dry_run]
        log.warn('Will delete record (Node="%s" Type="%s" RecordID="%s")' %
          [record[:node], options[:type], record[:record_id]])
      else
        c.soap_call('RecordDelete!', { 'record_id' => record[:record_id] })
        if c.response_hash[:status] == 'success'
          log.warn('Deleted record (Node="%s" Type="%s" RecordID="%s")' %
            [record[:node], options[:type], record[:record_id]])
        else
          log.warn('Failed to delete record (Node="%s" Type="%s" RecordID="%s") - %s' %
            [record[:node], options[:type], record[:record_id], c.response_messages])
        end
      end
    end

    # loop through each rdata
    if options[:rdata]
      rdata_hash_opts = c.rdata_hash_opts(options[:type])
      options[:rdata].each do |rdata|

        # check number of parameters
        if rdata.split(' ').length != rdata_hash_opts.length && options[:type] != 'TXT'
          log.error('%s records require %s parameter(s) (%s) but %d parameter(s) were given (%s)' %
            [options[:type], rdata_hash_opts.length, rdata_hash_opts.join(', '), rdata.split(' ').length, rdata.split(' ').join(', ')])
        else

          # format rdata options for new record
          # FIXME: TXT records always get quoted - dynect bug?
          rdata_formatted = {}
          case options[:type]
          when 'TXT'
            rdata_formatted[rdata_hash_opts[0]] = ['']
            rdata.split(' ').each do |value|
              rdata_formatted[rdata_hash_opts[0]] << value
            end
          else
            rdata.split(' ').each do |value|
              rdata_formatted[rdata_hash_opts[rdata_formatted.length]] = value
            end
          end

          # add new record
          if options[:dry_run]
            log.warn('Will create record (Zone="%s", Node="%s" TTL="%s", Type="%s", Data="%s")' %
              [options[:zone], options[:node], options[:ttl], options[:type], rdata])
          else
            c.soap_call('RecordAdd!', {
              'zone'  => options[:zone],
              'node'  => options[:node],
              'type'  => options[:type],
              'ttl'   => options[:ttl],
              'rdata' => rdata_formatted
            })
            if c.response_hash[:status] == 'success'
              log.warn('Created record (Zone="%s", Node="%s" TTL="%s", Type="%s", Data="%s")' %
                [options[:zone], options[:node], options[:ttl], options[:type], rdata])
            else
              log.error('Failed to create record (Zone="%s", Node="%s" TTL="%s", Type="%s", Data="%s") - %s' %
                [options[:zone], options[:node], options[:ttl], options[:type], rdata, c.response_messages])
            end
          end

        end

      end

    else

      # delete node if empty
      c.soap_call('RecordGet!', {
        'zone' => options[:zone],
        'node' => options[:node]
      })
      if !c.response_hash[:records].has_key?(:item)
        c.soap_call('NodeGet!', {
          'zone' => options[:zone],
          'node' => options[:node]
        })
        if c.response_hash[:status] == 'success'
          if options[:dry_run]
            log.warn('Will delete node (Zone="%s" Node="%s")' %
              [options[:zone], options[:node]])
          else
            c.soap_call('NodeDelete!', {
              'zone' => options[:zone],
              'node' => options[:node]
            })
            if c.response_hash[:status] == 'success'
              log.warn('Deleted node (Zone="%s" Node="%s")' %
                [options[:zone], options[:node]])
            else
              log.warn('Failed to delete node (Zone="%s" Node="%s") - %s' %
                [options[:zone], options[:node], c.response_messages])
            end
          end
        end
      end

    end

  end

end
