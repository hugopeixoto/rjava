require 'json'

module Objects
  Register = Struct.new(:index)
  RegisterRange = Struct.new(:begin, :end)
  Parameter = Struct.new(:index)
  ParameterRange = Struct.new(:begin, :end)
  MethodIdentifier = Struct.new(:class, :name, :args, :return_type)
  FieldIdentifier = Struct.new(:class, :name, :type)
  Label = Struct.new(:name)
  String = Struct.new(:text)
  Bytes = Struct.new(:value, :width) do
    def widen
      raise unless width == 32
      Bytes.new(value, 64)
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
      String.new(JSON.load(str)) # cheater
    elsif str.start_with?(':')
      Label.new(str)
    elsif str.start_with?("0x") || str.start_with?("-0x")
      v = str.to_i(16)
      Bytes.new(v, str.end_with?("L") ? 64 : 32)
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

      contents[register.index] = value
    end
  end

  class ParameterStorage
    attr_reader :contents
    def initialize(object, args)
      if object
        @contents = [object] + args
      else
        @contents = args
      end
    end

    def get(parameter)
      raise "Error accessing parameter: #{parameter} is not a parameter" unless parameter.is_a?(Parameter)
      raise "Error accessing parameter: #{parameter.index} is out of bounds" unless parameter.index < contents.size
      contents[parameter.index]
    end

    def set(parameter, value)
      raise "Error accessing parameter: #{parameter} is not a parameter" unless parameter.is_a?(Parameter)
      raise "Error accessing parameter: #{parameter.index} is out of bounds" unless parameter.index < contents.size

      contents[parameter.index] = value
    end
  end
end
