#!/usr/bin/env ruby

require_relative './parser'
require_relative './loader'
require_relative './stdlib'
require_relative './objects'

def debug_parse_instruction(inst)
  puts inst.ljust(100) + Parser.parse_instruction(inst).inspect
end

context = { classes: {} }

Stdlib.setup(context)

Dir["source/**/*.smali"].each do |f|
  Loader.load_file(f, context)
end

def convert_to_bool(value)
  JavaObject.new("Z", false)
end

def test_zero(value)
  case value
  when JavaObject
    case value.name
    when 'Z'
      value.value == false
    else
      raise "test-zero not supported for #{value.name}"
    end
  else
    raise "test-zero not supported for #{value}"
  end
end


run_context = { classes: {}, locks: [] }

JavaObject = Struct.new(:name, :value)
def new_object(context, run_context, klass)
  JavaObject.new(klass[1...-1])
end

def read_value(registers, parameters, arg)
  case arg
  when Objects::Register
    registers.get(arg)
  when Objects::Parameter
    parameters.get(arg)
  else
    raise "Can't read value: #{arg}"
  end
end

class Long
  def self.from_dalvik(value)
    raise "Expected long, got #{value}" unless value.is_a?(Objects::Bytes) && value.width == 64

    value.value
  end

  def self.to_dalvik(value)
    raise "expected integer" unless value.is_a?(Integer)
    raise "overflow" unless value < 2**63
    raise "underflow" unless value >= -2**63

    Objects::Bytes.new(value, 64)
  end
end

def binop_inner(sig, &block)
  types = sig.chars.map do |t|
    case t
    when 'L' then Long
    end
  end

  ->(lval, rval) do
    lval = types[0].from_dalvik(lval)
    rval = types[1].from_dalvik(rval)

    res = block.call(lval, rval)

    types[2].to_dalvik(res)
  end
end

def binop(inst, types, registers, parameters, &block)
  target = Objects.parse(inst.args[0])
  lval = Objects.parse(inst.args[1])
  rval = Objects.parse(inst.args[2])

  lval = read_value(registers, parameters, lval)
  rval = read_value(registers, parameters, rval)

  res = binop_inner(types) { |a, b| a + b }[lval, rval]

  registers.set(target, res)
end

def binop_2addr(inst, types, registers, parameters, &block)
  target = Objects.parse(inst.args[0])
  other = Objects.parse(inst.args[1])

  lval = read_value(registers, parameters, target)
  rval = read_value(registers, parameters, other)

  res = binop_inner(types, &block)[lval, rval]

  registers.set(target, res)
end

def initialize_class(context, run_context, klass)
  if klass.is_a? String
    class_name = klass
  else
    class_name = klass[:name]
  end

  if context[:classes][class_name].nil?
    raise "Class definition not found: #{class_name}"
  end

  if run_context[:classes][class_name].nil? && context[:classes][class_name][:methods].find { |m| m.name == "<clinit>" }
    run_context[:classes][class_name] = { fields: {} }
    run(context, run_context, class_name, "<clinit>")
  end
end

def set_static_field(context, run_context, identifier, value)
  raise "expected static field identifier, got #{identifier}" unless identifier.is_a?(Objects::FieldIdentifier)

  initialize_class(context, run_context, identifier.class)

  run_context[:classes][identifier.class][:fields][identifier.name] = value
end

def get_static_field(context, run_context, identifier)
  raise "expected static field identifier, got #{identifier}" unless identifier.is_a?(Objects::FieldIdentifier)

  initialize_class(context, run_context, identifier.class)

  run_context[:classes][identifier.class][:fields][identifier.name]
end

def run(context, run_context, class_name, method_name, this = nil, args = [])
  klass = context[:classes][class_name]
  if klass.nil?
    raise "Class definition not found: #{class_name}"
  end

  initialize_class(context, run_context, klass)

  method = context[:classes][class_name][:methods].find { |m| m.match?(method_name, this, args) }
  if method.nil?
    pp this, args
    raise "Method definition not found: #{class_name} -> #{method_name}. Methods: #{klass[:methods].map(&:signature)}"
  end

  pp "calling #{this || class_name}   #{method_name}   with #{args}"

  ip = 0
  registers = Objects::RegisterStorage.new(method.registers || 1)
  parameters = Objects::ParameterStorage.new(this, args)

  while method.instructions[ip]
    inst = method.instructions[ip]

    case inst.name
    when "const/4"
      target = Objects.parse(inst.args[0])
      value = Objects.parse(inst.args[1])

      raise "const-wide requires a 32bit value, got #{value}" unless value.width == 32
      registers.set(target, value)

    when "const/16"
      # const/16 v1, -0x119a
      target = Objects.parse(inst.args[0])
      value = Objects.parse(inst.args[1])

      raise "const-wide requires a 32bit value, got #{value}" unless value.width == 32
      registers.set(target, value)

    when "const-wide/16"
      target = Objects.parse(inst.args[0])
      value = Objects.parse(inst.args[1])

      raise "const-wide requires a 32bit value, got #{value}" unless value.width == 32
      registers.set(target, value.widen)
    when "const-wide/high16"
      # I don't understand this instruction. Does baksmali automatically pad this?
      target = Objects.parse(inst.args[0])
      value = Objects.parse(inst.args[1])

      raise "const-wide requires a 64bit value, got #{value}" unless value.width == 64
      registers.set(target, value)
    when "const-wide"
      target = Objects.parse(inst.args[0])
      value = Objects.parse(inst.args[1])

      raise "const-wide requires a 64bit value, got #{value}" unless value.width == 64

      registers.set(target, value)

    when "const-string"
      target = Objects.parse(inst.args[0])
      value = Objects.parse(inst.args[1])

      raise "#{inst.inspect}: const-string expects a string, got #{value}" unless value.is_a?(Objects::String)

      registers.set(target, value)

    when "sput-wide"
      value = Objects.parse(inst.args[0])
      identifier = Objects.parse(inst.args[1])

      value = read_value(registers, parameters, value)

      raise unless value.width == 64
      raise unless identifier.type == 'J'

      set_static_field(context, run_context, identifier, value)

    when "sput-boolean"
      value = Objects.parse(inst.args[0])
      identifier = Objects.parse(inst.args[1])

      value = read_value(registers, parameters, value)

      raise unless value.width == 32
      raise unless identifier.type == 'Z'

      set_static_field(context, run_context, identifier, value)

    when "new-instance"
      registers.set(Objects.parse(inst.args[0]), new_object(context, run_context, inst.args[1]))
    when "invoke-direct"
      obj, *args = inst.args[0].map { |arg| read_value(registers, parameters, Objects.parse(arg)) }
      identifier = Objects.parse(inst.args[1])

      raise unless identifier.is_a?(Objects::MethodIdentifier)

      initialize_class(context, run_context, identifier.class)
      run(context, run_context, identifier.class, identifier.name, obj, args)
    when "sput-object"
      value = Objects.parse(inst.args[0])
      identifier = Objects.parse(inst.args[1])

      value = read_value(registers, parameters, value)

      raise unless value.is_a?(JavaObject) || (value.is_a?(Objects::Bytes) && value.value == 0)
      raise unless identifier.type.start_with?("L")

      set_static_field(context, run_context, identifier, value)

    when "sget-wide"
      target = Objects.parse(inst.args[0])
      identifier = Objects.parse(inst.args[1])

      raise unless identifier.type == 'J'

      value = get_static_field(context, run_context, identifier)
      raise unless value.width == 64

      registers.set(target, value)

    when "sget-boolean"
      target = Objects.parse(inst.args[0])
      identifier = Objects.parse(inst.args[1])

      raise unless identifier.type == 'Z'

      value = get_static_field(context, run_context, identifier)
      raise unless value.width == 32

      registers.set(target, value)

    when "sget-object"
      target = Objects.parse(inst.args[0])
      identifier = Objects.parse(inst.args[1])

      raise unless identifier.type.start_with?("L")

      value = get_static_field(context, run_context, identifier)
      raise unless value.is_a?(JavaObject)

      registers.set(target, value)

    when "if-nez"
      value = Objects.parse(inst.args[0])
      label = Objects.parse(inst.args[1])

      value = read_value(registers, parameters, value)

      raise "#{inst.inspect}: expected 32b number, got #{value}" unless value.width == 32

      ip = method.labels[label.name] - 1 if value.value != 0

    when "if-gez"
      value = Objects.parse(inst.args[0])
      label = Objects.parse(inst.args[1])

      value = read_value(registers, parameters, value)

      raise "#{inst.inspect}: expected 32b number, got #{value}" unless value.width == 32

      ip = method.labels[label.name] - 1 if value.value >= 0

    when "cmp-long"
      target = Objects.parse(inst.args[0])
      lval = Objects.parse(inst.args[1])
      rval = Objects.parse(inst.args[2])

      lval = read_value(registers, parameters, lval)
      rval = read_value(registers, parameters, rval)

      raise "#{inst.inspect}: lval is not double: #{lval} (#{target})" unless lval.width == 64
      raise "#{inst.inspect}: rval is not double: #{rval} (#{other})" unless rval.width == 64

      lval = lval.value
      rval = rval.value

      result = lval <=> rval
      result = Objects::Bytes.new(result, 32)
      registers.set(target, result)

    when "cmpg-double"
      target = Objects.parse(inst.args[0])
      lval = Objects.parse(inst.args[1])
      rval = Objects.parse(inst.args[2])

      lval = read_value(registers, parameters, lval)
      rval = read_value(registers, parameters, rval)

      raise "#{inst.inspect}: lval is not double: #{lval} (#{target})" unless lval.width == 64
      raise "#{inst.inspect}: rval is not double: #{rval} (#{other})" unless rval.width == 64

      lval = [lval.value.to_s(16)].pack("H16").unpack("G").first
      rval = [rval.value.to_s(16)].pack("H16").unpack("G").first

      result = lval <=> rval || 1
      result = Objects::Bytes.new(result, 32)
      registers.set(target, result)

    when "long-to-int"
      raise "wip"
      registers[inst.args[0]] = registers[inst.args[1]] & 0xFFFFFFFF # ??
    when "or-int"
      raise "wip"
      registers[inst.args[0]] = read_value(inst.args[1], run_context, parameters, registers) | read_value(inst.args[2], run_context, parameters, registers)
    when "xor-int/lit8"
      raise "wip"
      registers[inst.args[0]] = read_value(inst.args[1], run_context, parameters, registers) ^ inst.args[2].to_i(16)
    when "or-int/2addr"
      raise "wip"
      registers[inst.args[0]] = registers[inst.args[0]] | read_value(inst.args[1], run_context, parameters, registers)
    when "and-int/2addr"
      raise "wip"
      registers[inst.args[0]] = registers[inst.args[0]] & read_value(inst.args[1], run_context, parameters, registers)

    when "xor-long/2addr"
      binop_2addr(inst, 'LLL', registers, parameters) { |a, b| a ^ b }

    when "or-long/2addr"
      binop_2addr(inst, 'LLL', registers, parameters) { |a, b| a | b }

    when "and-long/2addr"
      binop_2addr(inst, 'LLL', registers, parameters) { |a, b| a & b }

    when "add-long"
      binop(inst, 'LLL', registers, parameters) { |a, b| a + b }

    when "xor-long"
      binop(inst, 'LLL', registers, parameters) { |a, b| a ^ b }

    when "mul-double/2addr"
      target = Objects.parse(inst.args[0])
      other = Objects.parse(inst.args[1])

      lval = read_value(registers, parameters, target)
      rval = read_value(registers, parameters, other)

      raise "#{inst.inspect}: lval is not double: #{lval} (#{target})" unless lval.width == 64
      raise "#{inst.inspect}: rval is not double: #{rval} (#{other})" unless rval.width == 64

      lval = [lval.value.to_s(16)].pack("H16").unpack("G").first
      rval = [rval.value.to_s(16)].pack("H16").unpack("G").first
      lval = lval * rval
      lval = [lval].pack('G').unpack('H16').first.to_i(16)
      lval = Objects::Bytes.new(lval, 64)

      registers.set(target, lval)

    when "return-void"
      raise "#{inst}: return-void doesn't match method signature: #{method.return_type}" unless method.return_type == "V"

      run_context[:return] = nil
      return run_context[:return]

    #when "return"
    #  target = Objects.parse(inst.args[0])
    #  run_context[:return] = read_value(registers, parameters, target)
    #  return run_context[:return]

    when "return-wide"
      target = Objects.parse(inst.args[0])
      value = read_value(registers, parameters, target)

      raise "#{inst.inspect}: value is not double: #{value}" unless value.width == 64

      run_context[:return] = value
      return run_context[:return]

    when "move-result-wide"
      target = Objects.parse(inst.args[0])
      value = run_context[:return]

      raise "#{inst.inspect}: value is not double: #{value}" unless value.width == 64

      registers.set(target, value)

    when "invoke-static"
      arguments = inst.args[0].map { |a| Objects.parse(a) }
      identifier = Objects.parse(inst.args[1])

      run(context, run_context, identifier.class, identifier.name, nil, arguments)

    when "monitor-enter"
      lock = Objects.parse(inst.args[0])
      value = read_value(registers, parameters, lock)

      raise "must lock on a JavaObject, got #{value}" unless value.is_a?(JavaObject)

      if run_context[:locks].include?(value)
        raise "already locked"
      end

      run_context[:locks] << value

    else
      raise "unknown instruction: #{inst.inspect}"
    end
    ip += 1
  end

  run_context[:return] = nil
end

