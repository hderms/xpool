class XPool::Process
  #
  # @param [Fixnum] id
  #   The Process ID.
  #
  def initialize
    @channel = IChannel.new Marshal
    @busy_channel = IChannel.new Marshal
    @id = spawn
    @busy = false
  end

  #
  # A graceful shutdown of the process.
  #
  # The signal 'SIGUSR1' is caught in the subprocess and exit is
  # performed through Kernel#exit after the process has finished
  # executing its work.
  #
  # @return [void]
  #
  def shutdown
    _shutdown 'SIGUSR1' unless dead?
  end

  #
  # A non-graceful shutdown through SIGKILL.
  #
  # @return [void]
  #
  def shutdown!
    _shutdown 'SIGKILL' unless dead?
  end

  def schedule(unit,*args)
    @channel.put unit: unit, args: args
  end

  #
  # @return [Boolean]
  #   Returns true when the process is executing work.
  #
  def busy?
    if dead?
      false
    elsif @busy_channel.readable?
      begin
        @busy = @busy_channel.get
      end while @busy_channel.readable?
      @busy
    else
      @busy
    end
  end

  #
  # @return [Boolean]
  #   Returns true when the process is alive.
  #
  def alive?
    !dead?
  end

  #
  # @return [Boolean]
  #   Returns true when the process is no longer running.
  #
  def dead?
    @dead
  end

private
  def spawn
    fork do
      trap :SIGUSR1 do
        XPool.log "#{::Process.pid} got request to shutdown."
        @shutdown_requested = true
      end
      loop do
        begin
          if @channel.readable?
            @busy_channel.put true
            msg = @channel.get
            msg[:unit].run *msg[:args]
            @busy_channel.put false
          end
        ensure
          if @shutdown_requested && !@channel.readable?
            XPool.log "#{::Process.pid} is about to exit."
            break
          end
        end
      end
    end
  end

  def _shutdown(sig)
    begin
      Process.kill sig, @id
      Process.wait @id
    rescue SystemCallError
    ensure
      @dead = true
    end
  end
end
