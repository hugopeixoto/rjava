#!/usr/bin/env ruby

require_relative './parser'
require_relative './loader'
require_relative './stdlib'
require_relative './objects'

def debug_parse_instruction(inst)
  puts inst.ljust(100) + Parser.parse_instruction(inst).inspect
end


def load_program(source_glob)
  context = { classes: {} }

  Stdlib.setup(context)

  Dir[source_glob].each do |f|
    Loader.load_file(f, context)
  end

  context
end

def new_runtime
  { classes: {}, locks: [] }
end

JavaObject = Struct.new(:name, :value)
def new_object(context, run_context, klass)
  JavaObject.new(klass, {})
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

def read_value_wide(registers, parameters, arg)
  case arg
  when Objects::Register
    registers.get_wide(arg)
  when Objects::Parameter
    parameters.get_wide(arg)
  else
    raise "Can't read value: #{arg}"
  end
end

def read_value_type(registers, parameters, type, arg)
  if type == 'J'
    read_value_wide(registers, parameters, arg)
  else
    read_value(registers, parameters, arg)
  end
end

def store_value(registers, parameters, arg, value)
  case arg
  when Objects::Register
    registers.set(arg, value)
  when Objects::Parameter
    parameters.set(arg, value)
  else
    raise "Can't store value: #{arg}"
  end
end

def store_value_wide(registers, parameters, arg, value)
  case arg
  when Objects::Register
    registers.set_wide(arg, value)
  when Objects::Parameter
    parameters.set_wide(arg, value)
  else
    raise "Can't store value: #{arg}"
  end
end

class DalvikJ
  def self.from_dalvik(value)
    raise "Expected long, got #{value}" unless value.is_a?(Objects::Long)

    value.value
  end

  def self.to_dalvik(value)
    raise "expected integer" unless value.is_a?(Integer)
    raise "overflow" unless value < 2**63
    raise "underflow" unless value >= -2**63

    Objects::Long.new(value)
  end

  def self.mod(value)
    [value].pack("q>").unpack("q>").first
  end
end

class DalvikI
  def self.from_dalvik(value)
    raise "Expected integer, got #{value}" unless value.is_a?(Objects::Integer)

    value.value
  end

  def self.to_dalvik(value)
    raise "expected integer" unless value.is_a?(Integer)
    raise "overflow" unless value < 2**31
    raise "underflow" unless value >= -2**31

    Objects::Integer.new(value)
  end

  def self.mod(value)
    [value].pack("l>").unpack("l>").first
  end
end

def binop_inner(sig, &block)
  types = sig.chars.map do |t|
    case t
    when 'J' then DalvikJ
    when 'I' then DalvikI
    end
  end

  ->(lval, rval) do
    lval = types[1].from_dalvik(lval)
    rval = types[2].from_dalvik(rval)

    res = block.call(lval, rval)

    # raise "#{res} vs #{types[0].mod(res)}" if res != types[0].mod(res)
    types[0].to_dalvik(types[0].mod(res))
  end
end

def binop(inst, types, registers, parameters, &block)
  raise unless types.length == 3

  target = Objects.parse(inst.args[0])
  lval = Objects.parse(inst.args[1])
  rval = Objects.parse(inst.args[2])

  lval = read_value_type(registers, parameters, types[1], lval)
  rval = read_value_type(registers, parameters, types[2], rval)

  res = binop_inner(types, &block)[lval, rval]

  #puts [inst.name, lval.to_bits, rval.to_bits, res.to_bits].inspect

  if types[0] == 'J'
    store_value_wide(registers, parameters, target, res)
  else
    store_value(registers, parameters, target, res)
  end
end

def binop_lit8(inst, types, registers, parameters, &block)
  raise unless types.length == 3

  target = Objects.parse(inst.args[0])
  lval = Objects.parse(inst.args[1])
  rval = Objects.parse(inst.args[2])

  lval = read_value_type(registers, parameters, types[1], lval)

  res = binop_inner(types, &block)[lval, rval]

  store_value(registers, parameters, target, res)
end

def binop_2addr(inst, types, registers, parameters, &block)
  raise unless types.length == 2

  target = Objects.parse(inst.args[0])
  other = Objects.parse(inst.args[1])

  lval = read_value_type(registers, parameters, types[0], target)
  rval = read_value_type(registers, parameters, types[1], other)

  res = binop_inner(types[0] + types, &block)[lval, rval]

  if types[0] == 'J'
    store_value_wide(registers, parameters, target, res)
  else
    store_value(registers, parameters, target, res)
  end
end

def initialize_class(context, run_context, klass, depth)
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

    method = MethodLookup.new(context, run_context).lookup_static(Objects::MethodIdentifier.new(class_name, "<clinit>", "", "V"))
    run(context, run_context, method, nil, [], depth)
  end
end

def set_instance_field(context, run_context, identifier, this, value, depth)
  raise "expected field identifier, got #{identifier}" unless identifier.is_a?(Objects::FieldIdentifier)

  field = context[:classes][identifier.class][:fields][identifier.name]

  raise "field must be not static" if field[:modifiers].include?("static")
  raise "field #{field} can't store #{value}" if Objects.nil_value(field[:type]).class != value.class

  initialize_class(context, run_context, identifier.class, depth + 1)

  this.value[identifier.name] = value
end

def get_instance_field(context, run_context, identifier, this, depth)
  raise "expected field identifier, got #{identifier}" unless identifier.is_a?(Objects::FieldIdentifier)

  field = context[:classes][identifier.class][:fields][identifier.name]

  raise "field must be not static" if field[:modifiers].include?("static")

  initialize_class(context, run_context, identifier.class, depth + 1)

  this.value[identifier.name]
end

def set_static_field(context, run_context, identifier, value, depth)
  raise "expected field identifier, got #{identifier}" unless identifier.is_a?(Objects::FieldIdentifier)

  field = context[:classes][identifier.class][:fields][identifier.name]

  raise "field must be static" unless field[:modifiers].include?("static")

  initialize_class(context, run_context, identifier.class, depth + 1)

  type = field[:type]
  if type == 'I' && value.is_a?(JavaObject)
    raise unless value.name == "Ljava/lang/Integer;"

    value = value.value.fetch(:number)
  end

  run_context[:classes][identifier.class][:fields][identifier.name] = value
end

def get_static_field(context, run_context, identifier, depth)
  raise "expected static field identifier, got #{identifier}" unless identifier.is_a?(Objects::FieldIdentifier)

  initialize_class(context, run_context, identifier.class, depth + 1)

  run_context[:classes][identifier.class][:fields][identifier.name]
end

class MethodLookup < Struct.new(:context, :run_context)
  # TODO check class compat
  def lookup_direct(object, identifier)
    args = Parser.parse_types(identifier.args)

    raise "class not found: #{identifier.class}" unless context[:classes].key?(identifier.class)

    method = context[:classes][identifier.class][:methods]
      .reject { |m| m.modifiers.include?("static") }
      .find { |m| m.name == identifier.name && m.params == args }

    return method if method

    raise "direct method not found on #{object.name}: #{identifier}"
  end

  def lookup_virtual(object, identifier)
    class_name = object.name
    args = Parser.parse_types(identifier.args)

    raise "class not found: #{identifier.class}" unless context[:classes].key?(identifier.class)

    while class_name
      method = context[:classes][class_name][:methods]
        .reject { |m| m.modifiers.include?("static") }
        .find { |m| m.name == identifier.name && m.params == args }

      return method if method

      class_name = context[:classes][class_name][:super]
    end

    raise "virtual method not found: #{identifier}"
  end

  def lookup_static(identifier)
    args = Parser.parse_types(identifier.args)

    raise "class not found: #{identifier.class}" unless context[:classes].key?(identifier.class)

    method = context[:classes][identifier.class][:methods]
      .select { |m| m.modifiers.include?("static") }
      .find { |m| m.name == identifier.name && m.params == args }

    return method if method

    raise "static method not found: #{identifier}"
  end
end

def expects(args, types)
  args
    .map(&Objects.method(:parse))
    .tap do |values|
      values.zip(types).each do |(value, type)|
        raise "Expected #{type}, got #{value}" unless value.is_a?(type)
      end
    end
end

$debug = false
def run(context, run_context, method, this, args, depth = 0)
  puts " "*(depth*2) + "calling #{method.class_name}.#{method.name} with #{this} and #{args}"

  this = nil if method.modifiers.include?("static")
  initialize_class(context, run_context, this.name, depth + 1) if this

  if method.modifiers.include?("abstract")
    raise "calling abstract method, oh no"
  end

  if method.ruby_code
    run_context[:return] = method.ruby_code[this, args, context, run_context, depth]
  else
    parameters = Objects::ParameterStorage.new(this, args)
    registers = Objects::RegisterStorage.new(method.registers || 1)

    ip = 0
    while method.instructions[ip]
      inst = method.instructions[ip]

      case inst.name
      when "const"
        target, value = expects inst.args, [Objects::Register, Objects::Integer]
        registers.set(target, value)

      when "const/4"
        target, value = expects inst.args, [Objects::Register, Objects::Integer]
        registers.set(target, value)

      when "const/16"
        target, value = expects inst.args, [Objects::Register, Objects::Integer]
        registers.set(target, value)

      when "const-wide/16"
        target, value = expects inst.args, [Objects::Register, Objects::Integer]
        registers.set_wide(target, value.widen)

      when "const-wide/high16"
        target, value = expects inst.args, [Objects::Register, Objects::Long]
        registers.set_wide(target, value)

      when "const-wide"
        target, value = expects inst.args, [Objects::Register, Objects::Long]
        registers.set_wide(target, value)

      when "const-string"
        target, value = expects inst.args, [Objects::Register, JavaObject]

        raise "#{inst.inspect}: const-string expects a string, got #{value}" unless value.is_a?(JavaObject) && value.name == "Ljava/lang/String;"
        registers.set(target, value)
      when "const-string/jumbo"
        target, value = expects inst.args, [Objects::Register, JavaObject]

        raise "#{inst.inspect}: const-string expects a string, got #{value}" unless value.is_a?(JavaObject) && value.name == "Ljava/lang/String;"
        registers.set(target, value)

      when "sput"
        value = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)

        raise unless value.is_a?(Objects::Integer)
        raise unless identifier.type == 'I'

        set_static_field(context, run_context, identifier, value, depth)
      when "sput-wide"
        value = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        value = read_value_wide(registers, parameters, value)

        raise unless value.is_a?(Objects::Long)
        raise unless identifier.type == 'J'

        set_static_field(context, run_context, identifier, value, depth)

      when "sput-boolean"
        value = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)

        raise unless value.is_a?(Objects::Integer)
        raise unless identifier.type == 'Z'

        set_static_field(context, run_context, identifier, value, depth)

      when "new-instance"
        target = Objects.parse(inst.args[0])
        args = inst.args[1]

        registers.set(target, new_object(context, run_context, args))

      when "invoke-direct"
        identifier = Objects.parse(inst.args[1])

        raise unless identifier.is_a?(Objects::MethodIdentifier)

        values = inst.args[0].map { |arg| Objects.parse(arg) }
        values = values.map { |arg| read_value(registers, parameters, arg) }
        obj, *args = values

        submethod = MethodLookup.new(context, run_context).lookup_direct(obj, identifier)
        run(context, run_context, submethod, obj, args, depth + 1)

      when "invoke-virtual"
        identifier = Objects.parse(inst.args[1])

        raise unless identifier.is_a?(Objects::MethodIdentifier)

        values = inst.args[0].map { |arg| Objects.parse(arg) }
        values = values.map { |arg| read_value(registers, parameters, arg) }
        obj, *args = values

        submethod = MethodLookup.new(context, run_context).lookup_virtual(obj, identifier)
        run(context, run_context, submethod, obj, args, depth + 1)

      when "invoke-static"
        identifier = Objects.parse(inst.args[1])

        raise unless identifier.is_a?(Objects::MethodIdentifier)

        values = inst.args[0].map { |arg| Objects.parse(arg) }
        values = values.map { |arg| read_value(registers, parameters, arg) }

        submethod = MethodLookup.new(context, run_context).lookup_static(identifier)

        run(context, run_context, submethod, nil, values, depth + 1)

      when "sput-object"
        value = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)

        raise unless value.is_a?(JavaObject) || (value.is_a?(Objects::Integer) && value.value == 0)
        raise unless identifier.type.start_with?("L")

        set_static_field(context, run_context, identifier, value, depth)

      when "sget"
        target = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        raise unless identifier.type == 'I'

        value = get_static_field(context, run_context, identifier, depth)
        registers.set(target, value)

      when "sget-wide"
        target = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        raise unless identifier.type == 'J'

        value = get_static_field(context, run_context, identifier, depth)
        registers.set_wide(target, value)

      when "sget-boolean"
        target = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        raise unless identifier.type == 'Z'

        value = get_static_field(context, run_context, identifier, depth)
        registers.set(target, value)

      when "sget-object"
        target = Objects.parse(inst.args[0])
        identifier = Objects.parse(inst.args[1])

        raise unless identifier.type.start_with?("L")

        value = get_static_field(context, run_context, identifier, depth)
        raise unless value.is_a?(JavaObject)

        registers.set(target, value)

      when "iput"
        value = Objects.parse(inst.args[0])
        this = Objects.parse(inst.args[1])
        identifier = Objects.parse(inst.args[2])

        value = read_value(registers, parameters, value)
        this = read_value(registers, parameters, this)

        raise "iput needs a i32, got #{value}" unless value.is_a?(Objects::Integer)

        set_instance_field(context, run_context, identifier, this, value, depth)

      when "iput-object"
        value = Objects.parse(inst.args[0])
        this = Objects.parse(inst.args[1])
        identifier = Objects.parse(inst.args[2])

        value = read_value(registers, parameters, value)
        this = read_value(registers, parameters, this)

        raise "iput needs an object, got #{value}" unless value.is_a?(JavaObject)

        set_instance_field(context, run_context, identifier, this, value, depth)

      when "aput"
        value = Objects.parse(inst.args[0])
        array = Objects.parse(inst.args[1])
        index = Objects.parse(inst.args[2])

        value = read_value(registers, parameters, value)
        array = read_value(registers, parameters, array)
        index = read_value(registers, parameters, index)

        raise "aput target must be an array, got #{array}" unless array.is_a?(Objects::Array)
        raise "aput value must be a i32, got #{value}" unless value.is_a?(Objects::Integer)
        raise "aput index must be a i32, got #{index}" unless index.is_a?(Objects::Integer)

        array.set(index.value, value)

      when "iget"
        target = Objects.parse(inst.args[0])
        this = Objects.parse(inst.args[1])
        identifier = Objects.parse(inst.args[2])

        this = read_value(registers, parameters, this)
        value = get_instance_field(context, run_context, identifier, this, depth)

        raise "iget needs a i32, got #{value}" unless value.is_a?(Objects::Integer)

        registers.set(target, value)

      when "iget-object"
        target = Objects.parse(inst.args[0])
        this = Objects.parse(inst.args[1])
        identifier = Objects.parse(inst.args[2])

        this = read_value(registers, parameters, this)
        value = get_instance_field(context, run_context, identifier, this, depth)

        raise "iput needs an object, got #{value}" unless value.is_a?(JavaObject)

        registers.set(target, value)

      when "if-nez"
        value = Objects.parse(inst.args[0])
        label = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)

        raise "#{inst.inspect}: expected 32b number, got #{value}" unless value.is_a?(Objects::Integer)

        if value.value != 0
          ip = method.labels[label.name] - 1
        end

      when "if-gez"
        value = Objects.parse(inst.args[0])
        label = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)

        raise "#{inst.inspect}: expected 32b number, got #{value}" unless value.is_a?(Objects::Integer)

        if value.value >= 0
          ip = method.labels[label.name] - 1
        end

      when "if-eqz"
        value = Objects.parse(inst.args[0])
        label = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)

        raise "#{inst.inspect}: expected 32b number, got #{value}" unless value.is_a?(Objects::Integer)

        if value.value == 0
          ip = method.labels[label.name] - 1
        end

      when "if-ge"
        a = Objects.parse(inst.args[0])
        b = Objects.parse(inst.args[1])
        label = Objects.parse(inst.args[2])

        a = read_value(registers, parameters, a)
        b = read_value(registers, parameters, b)

        raise "#{inst.inspect}: expected 32b number, got #{a}" unless a.is_a?(Objects::Integer)
        raise "#{inst.inspect}: expected 32b number, got #{b}" unless b.is_a?(Objects::Integer)

        if a.value >= b.value
          ip = method.labels[label.name] - 1
        end

      when "goto"
        label = Objects.parse(inst.args[0])

        ip = method.labels[label.name] - 1

      when "cmp-long"
        target = Objects.parse(inst.args[0])
        lval = Objects.parse(inst.args[1])
        rval = Objects.parse(inst.args[2])

        lval = read_value_wide(registers, parameters, lval)
        rval = read_value_wide(registers, parameters, rval)

        raise "#{inst.inspect}: lval is not double: #{lval} (#{target})" unless lval.is_a?(Objects::Long)
        raise "#{inst.inspect}: rval is not double: #{rval} (#{other})" unless rval.is_a?(Objects::Long)

        lval = lval.value
        rval = rval.value

        result = lval <=> rval
        result = Objects::Integer.new(result)
        registers.set(target, result)

      when "cmpg-double"
        target = Objects.parse(inst.args[0])
        lval = Objects.parse(inst.args[1])
        rval = Objects.parse(inst.args[2])

        lval = read_value_wide(registers, parameters, lval)
        rval = read_value_wide(registers, parameters, rval)

        raise "#{inst.inspect}: lval is not double: #{lval} (#{target})" unless lval.is_a?(Objects::Long)
        raise "#{inst.inspect}: rval is not double: #{rval} (#{other})" unless rval.is_a?(Objects::Long)

        lval = [lval.value.to_s(16)].pack("H16").unpack("G").first
        rval = [rval.value.to_s(16)].pack("H16").unpack("G").first

        result = lval <=> rval || 1
        result = Objects::Integer.new(result)
        registers.set(target, result)

      when "long-to-int"
        target = Objects.parse(inst.args[0])
        value = Objects.parse(inst.args[1])

        long = value = read_value_wide(registers, parameters, value)
        value = value.shorten

        registers.set(target, value)
      when "int-to-short"
        target = Objects.parse(inst.args[0])
        value = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)
        value.value = [value.value].pack('l!<')[0...2].unpack('s!<').first

        registers.set(target, value)

      when "xor-int"
        binop(inst, 'III', registers, parameters) { |a, b| a ^ b }
      when "xor-int/2addr"
        binop_2addr(inst, 'II', registers, parameters) { |a, b| a ^ b }
      when "xor-int/lit8"
        binop_lit8(inst, 'III', registers, parameters) { |a, b| a ^ b }
      when "xor-long"
        binop(inst, 'JJJ', registers, parameters) { |a, b| a ^ b }
      when "xor-long/2addr"
        binop_2addr(inst, 'JJ', registers, parameters) { |a, b| a ^ b }

      when "or-int"
        binop(inst, 'III', registers, parameters) { |a, b| a | b }
      when "or-int/2addr"
        binop_2addr(inst, 'II', registers, parameters) { |a, b| a | b }
      when "or-long"
        binop(inst, 'JJJ', registers, parameters) { |a, b| a | b }
      when "or-long/2addr"
        binop_2addr(inst, 'JJ', registers, parameters) { |a, b| a | b }

      when "and-int"
        binop(inst, 'III', registers, parameters) { |a, b| a & b }
      when "and-int/2addr"
        binop_2addr(inst, 'II', registers, parameters) { |a, b| a & b }
      when "and-long"
        binop(inst, 'JJJ', registers, parameters) { |a, b| a & b }
      when "and-long/2addr"
        binop_2addr(inst, 'JJ', registers, parameters) { |a, b| a & b }

      when "add-int"
        binop(inst, 'III', registers, parameters) { |a, b| a + b }
      when "add-int/2addr"
        binop_2addr(inst, 'II', registers, parameters) { |a, b| a + b }
      when "add-long"
        binop(inst, 'JJJ', registers, parameters) { |a, b| a + b }
      when "add-long/2addr"
        binop_2addr(inst, 'JJ', registers, parameters) { |a, b| a + b }

      when "sub-int/2addr"
        binop_2addr(inst, 'II', registers, parameters) { |a, b| a - b }
      when "sub-long"
        binop(inst, 'JJJ', registers, parameters) { |a, b| a - b }
      when "sub-long/2addr"
        binop_2addr(inst, 'JJ', registers, parameters) { |a, b| a - b }
      when "rsub-int/lit8"
        binop_lit8(inst, 'III', registers, parameters) { |a, b| b - a }

      when "rem-int/lit8"
        binop_lit8(inst, 'III', registers, parameters) { |a, b| a.remainder(b) }
      when "rem-int/lit16"
        binop_lit8(inst, 'III', registers, parameters) { |a, b| a.remainder(b) }

      when "shl-int/lit8"
        binop_lit8(inst, 'III', registers, parameters) { |a, b|
          [a].pack("l>").unpack("B*").first.then{|a|a[b..]+"0"*b}.then{|a|[a]}.pack("B*").unpack("l>").first
        }
      when "shl-long"
        binop(inst, 'JJI', registers, parameters) { |a, b|
          raise unless b < 0x40
          [a].pack("q>").unpack("B*").first.then{|a|a[b..]+"0"*b}.then{|a|[a]}.pack("B*").unpack("q>").first
        }
      when "shr-long"
        binop(inst, 'JJI', registers, parameters) { |a, b|
          raise unless b < 0x40
          [a].pack("q>").unpack("B*").first.then{|a|a[0]*b + a[...-b]}.then{|a|[a]}.pack("B*").unpack("q>").first
        }
      when "shr-long/2addr"
        binop_2addr(inst, 'JI', registers, parameters) { |a, b|
          raise unless b < 0x40
          [a].pack("q>").unpack("B*").first.then{|a|a[0]*b + a[...-b]}.then{|a|[a]}.pack("B*").unpack("q>").first
        }

      when "mul-long/2addr"
        binop_2addr(inst, 'JJ', registers, parameters) { |a, b| a * b }

      when "mul-double/2addr"
        target = Objects.parse(inst.args[0])
        other = Objects.parse(inst.args[1])

        lval = read_value_wide(registers, parameters, target)
        rval = read_value_wide(registers, parameters, other)

        raise "#{inst.inspect}: lval is not double: #{lval} (#{target})" unless lval.is_a?(Objects::Long)
        raise "#{inst.inspect}: rval is not double: #{rval} (#{other})" unless rval.is_a?(Objects::Long)

        lval = [lval.value.to_s(16)].pack("H16").unpack("G").first
        rval = [rval.value.to_s(16)].pack("H16").unpack("G").first
        res = lval * rval
        res = [res].pack('G').unpack('H16').first.to_i(16)
        res = Objects::Long.new(res)

        registers.set_wide(target, res)

      when "div-int/lit8"
        binop_lit8(inst, 'III', registers, parameters) { |a, b| a.abs/b.abs * (a/b <=> 0) }

      when "return-void"
        raise "#{inst}: return-void doesn't match method signature: #{method.return_type}" unless method.return_type == "V"

        #puts " " * (depth * 2) + "#{inst.inspect}: returning void"

        run_context[:return] = nil
        return run_context.fetch(:return)

      when "return"
        value = Objects.parse(inst.args[0])
        value = read_value(registers, parameters, value)

        raise "#{inst.inspect}: value is not an i32: #{value}" unless value.is_a?(Objects::Integer)

        run_context[:return] = value
        return run_context.fetch(:return)

      when "return-wide"
        target = Objects.parse(inst.args[0])
        value = read_value_wide(registers, parameters, target)

        raise "#{inst.inspect}: value is not double: #{value}" unless value.is_a?(Objects::Long)

        # puts " " * (depth * 2) + "#{inst.inspect}: returning #{value.inspect}"

        run_context[:return] = value
        return run_context.fetch(:return)

      when "return-object"
        value = Objects.parse(inst.args[0])
        value = read_value(registers, parameters, value)

        raise "#{inst.inspect}: value is not an object: #{value}" unless value.is_a?(JavaObject)

        #puts " " * (depth * 2) + "#{inst.inspect}: returning #{value.inspect}"

        run_context[:return] = value
        return run_context.fetch(:return)

      when "move"
        target = Objects.parse(inst.args[0])
        source = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, source)

        store_value(registers, parameters, target, value)

      when "move-wide"
        target = Objects.parse(inst.args[0])
        source = Objects.parse(inst.args[1])

        value = read_value_wide(registers, parameters, source)

        store_value_wide(registers, parameters, target, value)

      when "move-result"
        target = Objects.parse(inst.args[0])
        value = run_context.fetch(:return)

        raise "#{inst.inspect}: value not i32: #{value}" unless value.is_a?(Objects::Integer)

        registers.set(target, value)

      when "move-result-wide"
        target = Objects.parse(inst.args[0])
        value = run_context.fetch(:return)

        raise "#{inst.inspect}: value is not double: #{value.inspect}" unless value.is_a?(Objects::Long)

        registers.set_wide(target, value)

      when "move-result-object"
        target = Objects.parse(inst.args[0])
        value = run_context.fetch(:return)

        raise "#{inst.inspect}: value is not an object: #{value}" unless value.is_a?(JavaObject)

        registers.set(target, value)

      when "monitor-enter"
        lock = Objects.parse(inst.args[0])
        value = read_value(registers, parameters, lock)

        raise "must lock on a JavaObject, got #{value}" unless value.is_a?(JavaObject)

        if run_context[:locks].include?(value)
          raise "already locked"
        end

        run_context[:locks] << value

      when "monitor-exit"
        lock = Objects.parse(inst.args[0])
        value = read_value(registers, parameters, lock)

        raise "must unlock a JavaObject, got #{value}" unless value.is_a?(JavaObject)

        if !run_context[:locks].include?(value)
          raise "not locked"
        end

        run_context[:locks].reject! { |lock| lock == value }

      when "new-array"
        target = Objects.parse(inst.args[0])
        count = Objects.parse(inst.args[1])
        type = Parser.parse_types(inst.args[2])

        raise "#{inst}: must only specify one type" if type.count > 1
        raise "#{inst}: type must be an array" unless type.first.start_with?("[")

        type = type.first
        count = read_value(registers, parameters, count)

        array = Objects::Array.new(type[1..], count.value)

        registers.set(target, array)

      when 'packed-switch'
        value = Objects.parse(inst.args[0])
        label = Objects.parse(inst.args[1])

        value = read_value(registers, parameters, value)
        switch = method.switches.fetch(label.name)

        label_name = switch[:labels][value.value - switch[:starting_value]]

        ip = method.labels[label_name] - 1 if label_name

      when "check-cast"
        target = Objects.parse(inst.args[0])
        type = Parser.parse_types(inst.args[1]).first

        target = read_value(registers, parameters, target)

        raise "wip: exceptions not implemented" unless target.is_a?(JavaObject) && target.name == type
      else
        raise "unknown instruction: #{inst.inspect}"
      end
      ip += 1
    end

    #puts " " * (depth*2) + "end of instruction list"
    raise "no return: #{method.return_type}" if method.return_type != 'V'
    run_context[:return] = nil
  end
end
