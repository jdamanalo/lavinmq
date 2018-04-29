require "logger"
require "./consumer"

module AvalancheMQ
  class Client
    class Channel
      class Consumer
        getter no_ack, queue, unacked, tag, exclusive
        @log : Logger

        def initialize(@channel : Client::Channel, @tag : String, @queue : Queue,
                       @no_ack : Bool, @exclusive : Bool)
          @log = @channel.log.dup
          @log.progname += "/Consumer[#{@tag}]"
          @unacked = Deque(SegmentPosition).new
        end

        def accepts?
          @channel.prefetch_count.zero? || @unacked.size < @channel.prefetch_count
        end

        def deliver(msg, sp, queue, redelivered = false)
          @unacked << sp unless @no_ack

          @log.debug { "Getting delivery tag" }
          delivery_tag = @channel.next_delivery_tag(queue, sp, @no_ack, self)
          @log.debug { "Sending BasicDeliver" }
          @channel.send AMQP::Basic::Deliver.new(@channel.id, @tag,
                                                 delivery_tag,
                                                 redelivered,
                                                 msg.exchange_name, msg.routing_key)
          @channel.deliver(msg)
        end

        def ack(sp)
          if @unacked.delete(sp)
            @log.debug { "Ackin #{sp}. Unacked: #{@unacked.size}" }
          end
        end

        def reject(sp)
          if @unacked.delete(sp)
            @log.debug { "Rejecting #{sp}. Unacked: #{@unacked.size}" }
          end
        end

        def cancel
          @channel.send AMQP::Basic::Cancel.new(@channel.id, @tag, true)
        end

        def details
          {
            queue: {
              name: @queue.name,
              vhost: @queue.vhost
            },
            consumer_tag: @tag,
            exclusive: @exclusive,
            ack_required: !@no_ack
          }
        end

        def to_json(json : JSON::Builder)
          details.to_json(json)
        end
      end
    end
  end
end
