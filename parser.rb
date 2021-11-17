
module Parser
  def self.parse_instruction line
    line = line.strip

    name, rest = line.split(" ", 2)

    rest = "" if rest.nil?
    if rest.strip.empty?
      return { name: name, args: [] }
    end

    i = 0
    in_string = false
    in_escape = false
    in_range = false
    arg_stack = [[], nil]
    while i < rest.size
      case [rest[i], in_string, in_escape]
        in ['{', false, *]
          arg_stack[-1] = []
          arg_stack << nil
        in ['}', false, *]
          last_element = arg_stack.pop
          arg_stack[-1] << last_element if last_element
          arg_stack[-1] = arg_stack[-1].join("-") if in_range
          in_range = false
        in [',', false, *]
          last_element = arg_stack.pop
          arg_stack[-1] << last_element if last_element
          arg_stack << nil
        in [' ', false, *]
        in ['.', false, *]
          in_range = true
          last_element = arg_stack.pop
          arg_stack[-1] << last_element if last_element
          arg_stack << nil
        in ['\\', true, false]
          in_escape = true
          arg_stack[-1] ||= ""
          arg_stack.last << rest[i]
        in [*, true, true]
          in_escape = false
          arg_stack[-1] ||= ""
          arg_stack.last << rest[i]
        in ['"', false, *]
          in_string = true
          arg_stack[-1] ||= ""
          arg_stack.last << rest[i]
        in ['"', true, false]
          in_string = false
          arg_stack[-1] ||= ""
          arg_stack.last << rest[i]
        else
          arg_stack[-1] ||= ""
          arg_stack.last << rest[i]
      end
      i += 1
    end

    last_element = arg_stack.pop
    arg_stack[-1] << last_element if last_element

    { name: name, args: arg_stack.last }
  rescue
    raise "Unable to parse instruction: #{line}"
  end

  def self.remove_comments(line)
    in_string = false
    in_escape = false
    mark = nil
    line.chars.each_with_index do |c, i|
      if in_escape
        in_escape = false
      elsif c == '#' && !in_string
        mark = i
        break
      elsif c == '"' && !in_string
        in_string = true
      elsif c == '"' && in_string && !in_escape
        in_string = false
      elsif c == '\\' && in_string
        in_escape = true
      end
    end

    if mark
      line[...mark]
    else
      line
    end
  end

  def self.parse_identifier(identifier)
    klass, field = identifier.split("->")

    if field.include?("(")
      method_params = field.match(/(.*)\((.*)\)(.*)/).to_a[1..]

      { class: klass, name: method_params[0], args: method_params[1], return_type: method_params[2] }
    else
      fname, type = field.split(":")

      { class: klass, field: fname, type: type }
    end
  end

  def self.parse_types(str)
    types = [""]

    in_name = false
    str.chars.each do |c|
      case c
      when '['
        types.last << c
      when 'L'
        types.last << c
        in_name = true
      when ';'
        types.last << c
        types << ""
        in_name = false
      else
        if in_name
          types.last << c
        else
          types.last << c
          types << ""
        end
      end
    end

    types.reject(&:empty?)
  end
end
