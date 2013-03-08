class XPool::Process
  MAX_RETRIES = 3
  #
  # @return [XPool::Process]
  #   Returns an instance of XPool::Process
  #
  def initialize
    @channel= IChannel.new Marshal
    @busy_channel = IChannel.new Marshal
    @id = spawn
    @busy = false
    @frequency = 0
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

  #
  # @return [Fixnum]
  #   The number of times the process has been asked to schedule work.
  #
  def frequency
    @frequency
  end

  #
  # @param [#run] unit
  #   The unit of work
  #
  # @param [Object] *args
  #   A variable number of arguments to be passed to #run
  #
  # @raise [RuntimeError]
  #   When the process is dead.
  #
  # @return [XPool::Process]
  #   Returns self
  #
  def schedule(unit,*args)
    if dead?
      raise RuntimeError,
        "cannot schedule work on a dead process (with ID: #{@id})"
    end
    @frequency += 1
    @channel.put unit: unit, args: args
    self
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
  def _shutdown(sig)
    Process.kill sig, @id
    Process.wait @id
    @dead = true
  end

  def spawn(retries = nil)
    fork do
      trap :SIGUSR1 do
        XPool.log "#{::Process.pid} got request to shutdown."
        @shutdown_requested = true
      end
      begin
        @retries = 0 and (@retries + 1)
        loop &method(:read_loop)
      rescue StandardError => e
        XPool.log "#{::Process.pid} failed due to exception: #{e}."
      end
    end
  end

  def read_loop
    if @channel.readable?
      @busy_channel.put true
      msg = @channel.get
      begin
        msg[:unit].run *msg[:args]
      rescue StandardError => e
        @busy_channel.put false

        unless exceeds_max_retries? or reschedule_disabled?
          spawn(@retries)
        else
        XPool.log "#{::Process.pid} can't be rescheduled reschedule."
        end
      end
    end
  ensure
    @busy_channel.put false
    if @shutdown_requested && !@channel.readable?
      XPool.log "#{::Process.pid} is about to exit."
      exit 0
    end
  end
  def reschedule_disabled?
    false
  end
  def exceeds_max_retries? 
    @retries >= MAX_RETRIES
  end
end
