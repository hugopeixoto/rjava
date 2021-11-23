class Directive
  attr_reader :words
  def initialize(line)
    @words = line.split
  end

  def inspect
    words.join(" ")
  end
end

class ClassDirective < Directive
  def visibility
    words[1]
  end

  def modifiers
    words[2..-1]
  end

  def name
    words[-1]
  end
end

class SuperDirective < Directive
  def name
    words[1]
  end
end

class MethodDirective < Directive
  def modifiers
    words[1...-1]
  end

  def name
    words[-1][0...-1].split("(", 2).first
  end

  def args
    words[-1].match(/\((.*)\)/)[1]
  end

  def return_type
    words[-1].split(")").last
  end
end

class EndDirective < Directive
  def what
    words[1]
  end
end

class RegistersDirective < Directive
  def count
    words[1].to_i
  end
end

class FieldDirective < Directive
  def modifiers
    words[1...-1]
  end

  def name
    words[-1].split(":").first
  end

  def type
    words[-1].split(":").last
  end
end

class PackedSwitchDirective < Directive
  def starting_value
    words[1].to_i(16)
  end
end

class Label < Struct.new(:name); end
class Instruction
  attr_reader :params
  def initialize(line)
    @params = Parser.parse_instruction(line)
  end

  def name
    params[:name]
  end

  def args
    params[:args]
  end
end


def directive(line)
  case line.split.first[1..]
  when "class"
    ClassDirective.new(line)
  when "super"
    SuperDirective.new(line)
  when "method"
    MethodDirective.new(line)
  when "end"
    EndDirective.new(line)
  when "registers"
    RegistersDirective.new(line)
  when "field"
    FieldDirective.new(line)
  when "packed-switch"
    PackedSwitchDirective.new(line)
  end
end

def parse(line)
  if line.start_with?(".")
    directive(line)
  elsif line.start_with?(":")
    Label.new(line)
  else
    Instruction.new(line)
  end
end


class JavaMethod
  attr_reader :class_name, :name, :modifiers, :return_type, :params
  attr_reader :labels, :instructions, :registers, :switches
  attr_reader :ruby_code
  def initialize(class_name, obj)
    @class_name = class_name
    @name = obj.name
    @modifiers = obj.modifiers
    @return_type = obj.return_type
    @params = Parser.parse_types(obj.args)

    @labels = {}
    @instructions = []
    @switches = {}
  end

  def set_ruby_code(block)
    @ruby_code = block
  end

  def set_registers(count)
    @registers = count
  end

  def add_label(name)
    @labels[name] = @instructions.count
  end

  def add_instruction(inst)
    @instructions << inst
  end

  def add_switch(switch)
    @switches[switch[:name]] = switch
  end

  def signature
    "#{modifiers.join(" ")} #{name}(#{params})#{return_type}"
  end

  def match?(name, this, args)
    #pp [name, this.nil?, args]
    #pp [self.name, self.modifiers.include?("static"), self.params]
    return false if name != self.name
    return false if this.nil? != self.modifiers.include?("static")
    return false if args.count != self.params.count

    true
  end
end

module Loader
  def self.load_file(filename, context)
    self.load(File.read(filename), context)
  end

  def self.load(content, context)
    lines = content.lines.map { |line| Parser.remove_comments(line).strip }.reject(&:empty?)

    current_class = nil
    current_method = nil
    current_switch = false
    last_label = nil
    lines.each do |line|
      d = parse(line)
      case d
      when ClassDirective
        current_class = context[:classes][d.name] = {
          name: d.name,
          visibility: d.visibility,
          methods: [],
          fields: {},
        }
      when SuperDirective
        current_class[:super] = d.name
      when FieldDirective
        current_class[:fields][d.name] = {
          class: current_class[:name],
          name: d.name,
          modifiers: d.modifiers,
          type: d.type,
        }
      when MethodDirective
        current_method = JavaMethod.new(current_class[:name], d)
        current_class[:methods] << current_method
      when EndDirective
        if d.what == "method" && current_method
          current_method = nil
        elsif d.what == "packed-switch" && current_switch
          current_switch = nil
        end
      when PackedSwitchDirective
        current_switch = {
          name: last_label,
          starting_value: d.starting_value,
          labels: [],
        }
        current_method.add_switch(current_switch)
      when RegistersDirective
        current_method.set_registers(d.count)
      when Label
        if current_switch
          current_switch[:labels] << d.name
        else
          current_method.add_label(d.name)
          last_label = d.name
        end
      when Instruction
        if current_method
          current_method.add_instruction(d)
        end
      else
        #puts "warning: unknown directive #{d}"
      end
    end
  end
end
