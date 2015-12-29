require 'pi_piper'

class BartenderController
  include Singleton

  attr_reader :current_step, :current_position

  def initialize
    @calibrated = false

    @current_step = 0
    @current_position = 0

    @sensor_pin_number = 5
    @pin_numbers = [6, 13, 19, 26]

    four_step!
    set_position_count! 6
  end

  def four_step!
    @full_rotation_steps = 2048
    @motor_step_sequence = [[1,1,0,0], [0,1,1,0], [0,0,1,1], [1,0,0,1]]

    set_movement_variables
  end
  def eight_step!
    @full_rotation_steps = 4096
    @motor_step_sequence = [[1,0,0,0], [1,1,0,0], [0,1,0,0], [0,1,1,0], [0,0,1,0], [0,0,1,1], [0,0,0,1], [1,0,0,1]]

    set_movement_variables
  end

  def set_position_count!(count)
    @available_positions = count
    set_movement_variables
  end

  def spin_to_position!(destination)
    calibrate! unless @calibrated

    displacement = destination - @current_position
    halfway_point = @available_positions / 2

    steps = if displacement > halfway_point
      displacement - @available_positions
    else
      displacement < (halfway_point * -1) ? displacement + @available_positions : displacement
    end

    rotate(steps)

    @current_position
  end

  private

  def set_movement_variables
    return unless @full_rotation_steps && @available_positions
    @position_steps = @full_rotation_steps / @available_positions
  end

  def registered_pins
    @registered_pins ||= []
  end
  def registered_pin_numbers
    @registered_pins.map { |pin| pin.pin }
  end
  def pin_registered?(pin_number)
    registered_pin_numbers.include?(pin_number)
  end

  def register_pin(number, direction = :out)
    pin = PiPiper::Pin.new(pin: number, direction: direction)
    @registered_pins << pin

    pin
  end
  def release_pins(pin_numbers = nil)
    pins_to_release = pin_numbers.is_a?(Array) ? pin_numbers : [pin_numbers] if !!pin_numbers
    pins_to_release ||= registered_pin_numbers
    pins_to_release = opened_pins if pins_to_release.empty?

    pins_to_release.each do |pin_number|
      begin
        File.open("/sys/class/gpio/unexport", "w") { |f| f.write(pin_number.to_s) } if pin_open?(pin_number)
        @registered_pins.delete_if { |pin| pin.pin == pin_number }
      rescue => e
        puts "!! > Error closing GPIO PIN##{pin_number}: #{e.message}"
      end
    end
  end

  def opened_pins
    Dir.glob('/sys/class/gpio/gpio*').map { |s| s.scan(/gpio([0-9]+)/) }.flatten.map(&:to_i)
  end
  def pin_open?(pin_number)
    opened_pins.include?(pin_number)
  end

  def rotate(steps)
    # direction = steps ** 0
    direction = steps < 0 ? -1 : 1

    steps.abs.times do
      @position_steps.times { rotate_direction(direction) }

      if @calibrated
        @current_position += direction
        @current_position %= @available_positions
      end
    end

    clean_motor_pin_state!

    @current_position
  end
  def rotate_direction(direction)
    @current_step -= direction
    @current_step %= @motor_step_sequence.size

    step = @motor_step_sequence[@current_step]

    step.each_with_index do |io, index|
      io == 1 ? @motor_pins[index].on : @motor_pins[index].off
    end

    sleep 0.001

    nil
  end

  def next_position!(direction = 1)
    spin_to_position((@current_position + direction) % @available_positions)
  end

  def register_motor_pins
    release_pins
    @motor_pins = @pin_numbers.map { |number| register_pin(number) }

    calibrate!
  end
  def clean_motor_pin_state!
    @motor_pins.each(&:off)
    nil
  end

  def sensor_pin
    @sensor_pin = nil unless pin_registered?(@sensor_pin_number)
    @sensor_pin ||= register_pin(@sensor_pin_number, :in)
  end
  def sensor_tripped?(safe = true)
    return sensor_pin.read == PiPiper::PinValues::GPIO_HIGH unless safe

    5.times do
      return true if sensor_pin.read == PiPiper::PinValues::GPIO_HIGH
      sleep 0.005
    end

    false
  end

  def calibrate!
    return register_motor_pins unless @motor_pins
    raise 'Failed to calibrate sensors' unless calibrate_motor_position
  end
  def calibrate_motor_position
    @calibrated = false

    if sensor_tripped?
      rotate 1

      return false if sensor_tripped?

      release_pins @sensor_pin_number
      return false if sensor_tripped?
    end

    until sensor_tripped?(false) do
      rotate_direction 1
    end

    clean_motor_pin_state!
    @current_position = 0
    @calibrated = true
  end
end
