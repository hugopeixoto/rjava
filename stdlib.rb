require 'ostruct'
require_relative './loader'
require_relative './objects'

module Stdlib
  def self.setup(context)
    Loader.load(<<-EOF, context)
      .class public Ljava/lang/Object;

      .method public constructor <init>()V
      .end method
    EOF

    Loader.load(<<-EOF, context)
      .class public Ljavax/crypto/spec/IvParameterSpec;

      #.method public constructor <init>([B)V
      #.end method
    EOF

    Loader.load(<<-EOF, context)
      .class public Ljava/lang/Math;

      .method public static random()D
        .registers 2
        const-wide v0, 0x0L
        return-wide v0
      .end method
    EOF

    Loader.load(<<-EOF, context)
      .class public Ljava/util/Random;
      .method public constructor <init>()V
      .end method
    EOF

    Loader.load(<<-EOF, context)
      .class public Ljava/lang/String;
    EOF

    add_ruby_method(context, "Ljava/lang/String;->length()I") do |this, args|
      Objects::Integer.new(this.value.fetch(:contents).length)
    end

    add_ruby_method(context, "Ljava/lang/String;->charAt(I)C") do |this, args|
      Objects::Integer.new(this.value.fetch(:contents)[args[0].value].ord)
    end

    # String(int[] codePoints, int offset, int count)
    add_ruby_method(context, "Ljava/lang/String;-><init>([III)V") do |this, (codepoints, offset, count)|
      this.value[:contents] = codepoints.values.map(&:value)[offset.value...count.value].pack("U*")
    end

    Loader.load(<<-EOF, context)
      .class public Ljava/lang/Class;
    EOF

    add_ruby_method(context, "Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;", %w[static]) do |this, args|
      name = "L#{args[0].value[:contents].gsub(".", "/")};"

      raise "couldn't find class #{name}" unless context[:classes].keys.include?(name)

      JavaObject.new("Ljava/lang/Class;", { name: name })
    end

    add_ruby_method(context, "Ljava/lang/Class;->getDeclaredMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;") do |this, args|
      #found: #<struct Objects::MethodIdentifier class="Ljava/lang/Class;", name="getDeclaredMethod", args="Ljava/lang/String;[Ljava/lang/Class;", return_type="Ljava/lang/reflect/Method;"> (RuntimeError)

      same_name_methods = context[:classes][this.value[:name]][:methods].select { |m| m.name == args[0].value[:contents] }

      raise if same_name_methods.count > 1

      JavaObject.new("Ljava/lang/reflect/Method;", { method: same_name_methods.first })
    end

    add_ruby_method(context, "Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;") do |this, args|
      field = context[:classes].fetch(this.value.fetch(:name)).fetch(:fields).fetch(args[0].value.fetch(:contents))

      JavaObject.new("Ljava/lang/reflect/Field;", { field: field })
    end

    Loader.load(<<-EOF, context)
      .class public Ljava/lang/reflect/Field;
    EOF

    add_ruby_method(context, "Ljava/lang/reflect/Field;->setAccessible(Z)V") do |this, args|
    end

    add_ruby_method(context, "Ljava/lang/reflect/Field;->set(Ljava/lang/Object;Ljava/lang/Object;)V") do |this, args, context, run_context, depth|
      target = args[0]
      value = args[1]

      if this.value[:field][:modifiers].include?("static")
        # Leg/щ;->Ŭ:J
        identifier = Objects.parse("#{this.value[:field][:class]}->#{this.value[:field][:name]}:#{this.value[:field][:type]}")
        set_static_field(context, run_context, identifier, value, depth)
      else
        raise "wip"
      end
    end

    add_ruby_method(context, "Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;") do |this, args, context, run_context, depth|
      target = args[0]

      if this.value[:field][:modifiers].include?("static")
        identifier = Objects.parse("#{this.value[:field][:class]}->#{this.value[:field][:name]}:#{this.value[:field][:type]}")
        value = get_static_field(context, run_context, identifier, depth)

        if value.is_a?(Objects::Integer)
          JavaObject.new("Ljava/lang/Integer;", { number: value })
        else
          raise "wip"
        end
      else
        raise "wip"
      end
    end

    add_ruby_method(context, "Ljava/lang/String;->valueOf(I)Ljava/lang/String;", %w[static]) do |this, args|
      JavaObject.new("Ljava/lang/String;", { contents: args[0].value.to_s })
    end

    add_ruby_method(context, "Ljava/lang/String;->valueOf(J)Ljava/lang/String;", %w[static]) do |this, args|
      JavaObject.new("Ljava/lang/String;", { contents: args[0].pair(args[1]).value.to_s })
    end

    Loader.load(<<-EOF, context)
      .class public Landroid/util/Log;
    EOF

    add_ruby_method(context, "Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I", %w[static]) do |this, args|
      tag = args[0].value[:contents]
      puts "#{tag}: #{args[1..]}"
    end

    Loader.load(<<-EOF, context)
      .class public Ljava/lang/reflect/Method;
    EOF

    add_ruby_method(context, "Ljava/lang/reflect/Method;->setAccessible(Z)V") do |this, args|
    end

    add_ruby_method(context, "Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;") do |this, args, context, run_context, depth|
      run(context, run_context, this.value[:method], args[0], args[1].values, depth + 1)
    end

    Loader.load(<<-EOF, context)
      .class public abstract Ljava/util/Timer;

      .method public constructor <init>()V
      .end method
    EOF

    add_ruby_method(context, "Ljava/util/Timer;->schedule(Ljava/util/TimerTask;J)V") do |this, args|
      pp [this, args]
      raise "wip"
    end

    Loader.load(<<-EOF, context)
      .class public Ljava/util/TimerTask;
      .method public constructor <init>()V
      .end method
    EOF

    Loader.load(<<-EOF, context)
      .class public Ljava/lang/Integer;
    EOF

    add_ruby_method(context, "Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;", %w[static]) do |this, args|
      JavaObject.new("Ljava/lang/Integer;", { number: args[0] })
    end

    add_ruby_method(context, "Ljava/lang/Integer;->intValue()I") do |this, args|
      this.value.fetch(:number)
    end
  end

  def self.add_ruby_method(context, method_identifier, modifiers = [], &block)
    method_identifier = Objects.parse(method_identifier)

    m = JavaMethod.new(method_identifier.class, OpenStruct.new(
      name: method_identifier.name,
      modifiers: modifiers,
      return_type: method_identifier.return_type,
      args: method_identifier.args,
    ))

    m.set_ruby_code block

    context[:classes][method_identifier.class][:methods] << m
  end
end
