require 'json'

module Objects
  Register = Struct.new(:index) do
    def next
      Register.new(index + 1)
    end

    def to_s
      "Register(#{index})"
    end
  end

  RegisterRange = Struct.new(:begin, :end)
  Parameter = Struct.new(:index) do
    def next
      Parameter.new(index + 1)
    end
  end
  ParameterRange = Struct.new(:begin, :end)
  MethodIdentifier = Struct.new(:class, :name, :args, :return_type)
  FieldIdentifier = Struct.new(:class, :name, :type)
  Label = Struct.new(:name)

  Integer = Struct.new(:value) do
    def self.zero
      new(0)
    end

    def pair(lo)
      Long.new([value, lo.value].pack("l>l>").unpack("q>").first)
    end

    def widen
      Long.new(value)
    end

    def to_bits
      [value].pack("l>").unpack("B*").first
    end
  end

  Long = Struct.new(:value) do
    def self.zero
      new(0)
    end

    def shorten
      Integer.new([value].pack("q>")[4..].unpack("l>").first)
    end

    def to_bits
      [value].pack("q>").unpack("B*").first
    end
  end

  def self.nil_value(type)
    case type
    when 'Z' then Integer.zero
    when 'B' then Integer.zero
    when 'S' then Integer.zero
    when 'C' then Integer.zero
    when 'I' then Integer.zero
    when 'J' then Long.zero
    when 'F' then Integer.zero
    when 'D' then Long.zero
    when 'Ljava/lang/String;' then JavaObject.new(type, { contents: "" })
    when 'V' then raise
    else nil
    end
  end

  class Array
    attr_reader :type, :values
    def initialize(type, length)
      @values = [Objects.nil_value(type)] * length
    end

    def length
      values.length
    end

    def set(index, value)
      raise "array index underflow: #{index}" if index < 0
      raise "array index overflow: #{index}/#{length}" if index >= length

      @values[index] = value
    end
  end

  def self.parse(str)
    if str.start_with?("v")
      parts = str.split('-')
      if parts.size == 1
        Register.new(str[1..].to_i)
      else
        RegisterRange.new(parts[0][1..].to_i, parts[1][1..].to_i)
      end
    elsif str.start_with?("p")
      parts = str.split('-')
      if parts.size == 1
        Parameter.new(str[1..].to_i)
      else
        ParameterRange.new(parts[0][1..].to_i, parts[1][1..].to_i)
      end
    elsif str.start_with?("L")
      id = Parser.parse_identifier(str)

      if id.key?(:field)
        FieldIdentifier.new(id[:class], id[:field], id[:type])
      else
        MethodIdentifier.new(id[:class], id[:name], id[:args], id[:return_type])
      end
    elsif str.start_with?('"')
      JavaObject.new("Ljava/lang/String;", { contents: JSON.load(str) }) # cheater
    elsif str.start_with?(':')
      Label.new(str)
    elsif str.start_with?("0x") || str.start_with?("-0x")
      v = str.to_i(16)

      str.end_with?("L") ? Long.new(v) : Integer.new(v)
    end
  end

  class RegisterStorage
    attr_reader :contents
    def initialize(count)
      @contents = [nil] * count
    end

    def get(register)
      raise "Error accessing register: #{register} is not a register" unless register.is_a?(Register)
      raise "Error accessing register: #{register.index} is out of bounds" unless register.index < contents.size
      contents[register.index]
    end

    def set(register, value)
      raise "Error accessing register: #{register} is not a register" unless register.is_a?(Register)
      raise "Error accessing register: #{register.index} is out of bounds" unless register.index < contents.size

      raise "Can't store #{value.inspect} in a register" unless value.is_a?(Integer) || value.is_a?(JavaObject) || value.is_a?(Array)

      contents[register.index] = value
    end

    def get_wide(register)
      hi = get(register)
      lo = get(register.next)

      raise "get_wide requires two 32b values" unless hi.is_a?(Objects::Integer)
      raise "get_wide requires two 32b values" unless lo.is_a?(Objects::Integer)

      value = [hi.value, lo.value].pack("l>l>").unpack("q>").first

      Long.new(value)
    end

    def set_wide(register, value)
      raise "set_wide requires a long value" unless value.is_a?(Long)

      binary = [value.value].pack("q>")
      hi = binary[0...4].unpack("l>").first
      lo = binary[4...8].unpack("l>").first

      set(register, Integer.new(hi))
      set(register.next, Integer.new(lo))
    end
  end

  class ParameterStorage
    attr_reader :contents
    def initialize(object, args)
      args = [object] + args if object

      @contents = [nil] * args.count

      args.each_with_index { |arg, index| set(Parameter.new(index), arg) }
    end

    def get(parameter)
      raise "Error accessing parameter: #{parameter} is not a parameter" unless parameter.is_a?(Parameter)
      raise "Error accessing parameter: #{parameter.index} is out of bounds" unless parameter.index < contents.size
      contents[parameter.index]
    end

    def set(parameter, value)
      raise "Error accessing parameter: #{parameter} is not a parameter" unless parameter.is_a?(Parameter)
      raise "Error accessing parameter: #{parameter.index} is out of bounds" unless parameter.index < contents.size

      raise "Can't store #{value} in a parameter" unless value.is_a?(Integer) || value.is_a?(JavaObject)

      contents[parameter.index] = value
    end

    def get_wide(parameter)
      hi = get(parameter)
      lo = get(parameter.next)

      raise "get_wide requires two 32b values" unless hi.is_a?(Objects::Integer)
      raise "get_wide requires two 32b values" unless lo.is_a?(Objects::Integer)

      value = [hi.value, lo.value].pack("l>l>").unpack("q>").first

      Long.new(value)
    end

    def set_wide(parameter, value)
      raise "set_wide requires a long value" unless value.is_a?(Long)

      binary = [value.value].pack("q>")
      hi = binary[0...4].unpack("l>").first
      lo = binary[4...8].unpack("l>").first

      set(parameter, Integer.new(hi))
      set(parameter.next, Integer.new(lo))
    end
  end
end
