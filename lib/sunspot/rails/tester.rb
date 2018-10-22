require 'net/http'
require 'forwardable'

module Sunspot
  module Rails

    class SunspotRefusesToStartError < StandardError; end

    class Tester
      VERSION = '1.0.0'

      class << self
        extend Forwardable

        attr_accessor :server, :started, :pid
        attr_accessor :retries, :timeout

        def start_original_sunspot_session
          @retries ||= 3
          @timeout ||= 20

          begin
            unless started?
              self.server = Sunspot::Rails::Server.new
              self.started = Time.now
              self.pid = fork do
                $stderr.reopen('/dev/null')
                $stdout.reopen('/dev/null')
                server.run
              end
              kill_at_exit
              give_feedback
            end
          rescue SunspotRefusesToStartError
            @retries -= 1

            if @retries > 0
              puts "Sunspot not starting - retrying"
              kill_process
              self.server = nil
              self.pid = nil
              sleep(2)
              retry
            else
              puts "Sunspot server failed to start after multiple retries"
            end
          end
        end

        def started?
          not server.nil?
        end

        def kill_process
          Process.kill('TERM', pid)
        end

        def kill_at_exit
          at_exit { kill_process }
        end

        def give_feedback
          loop.with_index do |_, i|
            break unless starting
            raise SunspotRefusesToStartError if startup_seconds > @timeout

            STDOUT.write "\rSunspot server is starting...#{'.' * i}"
          end
          puts "\nSunspot server took #{seconds} seconds to start"
        end

        def starting
          sleep(1)
          Net::HTTP.get_response(URI.parse(uri))
          false
        rescue Errno::ECONNREFUSED
          true
        end

        def startup_seconds
          Time.now - started
        end

        def seconds
          '%.2f' % startup_seconds
        end

        def uri
          "http://#{hostname}:#{port}#{path}"
        end

        def_delegators :configuration, :hostname, :port, :path

        def configuration
          server.send(:configuration)
        end

        def clear
          self.server = nil
        end
      end

    end
  end
end
