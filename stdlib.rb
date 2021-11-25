require 'ostruct'
require_relative './loader'
require_relative './objects'
require 'zip'

module Stdlib
  def self.setup(context)
    Loader.load(<<-EOF, context)
      .class public Ljava/lang/Object;

      .method public constructor <init>()V
      .end method
    EOF

    Loader.load(<<-EOF, context)
      .class public Landroid/app/Application;
      .super Landroid/content/ContextWrapper;

      .class public Landroid/content/ContextWrapper;
      .super Landroid/content/Context;

      .class public Landroid/content/Context;
      .class public Landroid/content/pm/PackageManager;
      .class public Landroid/content/pm/ApplicationInfo;
      .field public publicSourceDir:Ljava/lang/String;
      .field public splitPublicSourceDirs:[Ljava/lang/String;

      .class public static Landroid/os/Build$VERSION;
      .field public static final SDK_INT:I;

      .class public static Ljava/util/Arrays;

      .class public Ljava/security/MessageDigest;
      .class public Ljava/util/Map;

      .class public Ljava/util/TreeMap;
      .super Ljava/util/Map;

      .class Ljava/util/zip/ZipFile;
      .class Ljava/util/zip/ZipEntry;
      .class Ljava/util/Enumeration;
      .class Ljava/nio/charset/Charset;
      .class Ljava/nio/charset/StandardCharsets;
      .field public static final UTF_8:Ljava/nio/charset/Charset;
    EOF

    add_ruby_method(context, "Ljava/nio/charset/StandardCharsets;-><clinit>()V", %w[static constructor]) do |this, args, context, run_context, depth|
      set_static_field(
        context, run_context,
        Objects.parse("Ljava/nio/charset/StandardCharsets;->UTF_8:Ljava/nio/charset/Charset;"),
        JavaObject.new("Ljava/nio/charset/Charset;", { charset: "utf8" }),
        depth
      )
    end

    add_ruby_method(context, "Ljava/util/zip/ZipFile;-><init>(Ljava/lang/String;)V") do |this, args|
      this.value[:filename] = args[0]
    end

    add_ruby_method(context, "Ljava/util/zip/ZipFile;->getName()Ljava/lang/String;") do |this, args|
      this.value[:filename]
    end

    add_ruby_method(context, "Ljava/util/zip/ZipEntry;->getName()Ljava/lang/String;") do |this, args|
      this.value[:name]
    end

    add_ruby_method(context, "Ljava/util/zip/ZipFile;->entries()Ljava/util/Enumeration;") do |this, args|
      entries = Zip::ZipFile.open(this.value[:filename].value[:contents]).map(&:name)

      JavaObject.new("Ljava/util/Enumeration;", { items: entries, next_index: 0 })
    end

    add_ruby_method(context, "Ljava/util/Enumeration;->hasMoreElements()Z") do |this, args|
      if this.value[:next_index] < this.value[:items].length
        Objects::True
      else
        Objects::False
      end
    end

    add_ruby_method(context, "Ljava/util/Enumeration;->nextElement()Ljava/lang/Object;") do |this, args|
      JavaObject.new("Ljava/util/zip/ZipEntry;", { name: Objects.new_string(this.value[:items][this.value[:next_index]]) })
    end

    add_ruby_method(context, "Ljava/util/TreeMap;-><init>()V") do |this, args|
      this.value[:tree] = []
    end

    add_ruby_method(context, "Ljava/util/TreeMap;-><init>(Ljava/util/Map;)V") do |this, args|
      this.value[:tree] = args[0].value[:tree] + []
    end

    add_ruby_method(context, "Ljava/util/TreeMap;->size()I") do |this, args|
      Objects::Integer.new(this.value[:tree].size)
    end

    add_ruby_method(context, "Ljava/util/TreeMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;") do |this, args|
      pp ["inserting", args]
      index = this.value[:tree].index { |e| false }

      if index
        old = this.value[:tree][index]
        this.value[:tree][index] = args[1]

        old
      else
        Objects::Integer.new(0)
      end
    end


    add_ruby_method(context, "Ljava/security/MessageDigest;->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;", %w[static]) do |this, args|
      JavaObject.new("Ljava/security/MessageDigest;", { algorithm: args[0], update: [] })
    end

    add_ruby_method(context, "Ljava/security/MessageDigest;->update([B)V") do |this, args|
      this.value[:update] << args[0]
    end

    add_ruby_method(context, "Landroid/os/Build$VERSION;-><clinit>()V", %w[static constructor]) do |this, args, context, run_context, depth|
      set_static_field(context, run_context, Objects.parse("Landroid/os/Build$VERSION;->SDK_INT:I"), Objects::Integer.new(21), depth)
    end

    add_ruby_method(context, "Landroid/content/Context;->getPackageName()Ljava/lang/String;") do |this, args|
      JavaObject.new("Ljava/lang/String;", { contents: context[:package_name] })
    end

    add_ruby_method(context, "Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;") do |this, args|
      JavaObject.new("Landroid/content/pm/PackageManager;", {})
    end

    add_ruby_method(context, "Landroid/content/pm/PackageManager;->getApplicationInfo(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;") do |this, args, context|
      JavaObject.new("Landroid/content/pm/ApplicationInfo;", {
        "publicSourceDir" => JavaObject.new("Ljava/lang/String;", { contents: context[:apk_location] }),
        "splitPublicSourceDirs" => Objects::Array.new("Ljava/lang/String;", 0),
      })
    end

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
      same_name_methods = context[:classes][this.value[:name]][:methods]
        .select { |m| m.name == args[0].value[:contents] }
        .select { |m| m.params.length == args[1].length }

      if same_name_methods.count != 1
        pp this
        pp args
        pp same_name_methods.map(&:signature)
        raise "ambiguous getDeclaredMethod, found #{same_name_methods.count} matches"
      end

      JavaObject.new("Ljava/lang/reflect/Method;", { method: same_name_methods.first })
    end

    add_ruby_method(context, "Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;") do |this, args, context, run_context|
      pp this, args

      arg_types = args[1].values.map {|a| "I" }.join

      obj = JavaObject.new(this.value.fetch(:name), {})
      identifier = Objects.parse("#{this.value[:name]}->#{args[0].value[:contents]}(#{arg_types})V")
      method = MethodLookup.new(context, run_context).lookup_virtual(obj, identifier)

      raise unless method

      JavaObject.new("Ljava/lang/reflect/Method;", { method: method })

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
        elsif value.is_a?(JavaObject)
          value
        elsif value.is_a?(Objects::Array)
          value
        else
          pp [this, args, value]
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

    add_ruby_method(context, "Ljava/lang/String;->equals(Ljava/lang/Object;)Z") do |this, args|
      pp "comparing #{this} with #{args[0]}"

      if args[0].name == "Ljava/lang/String;"
        if args[0].value[:contents] == this.value[:contents]
          Objects::True
        else
          Objects::False
        end
      else
        raise "wip"
      end
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
      ret = run(context, run_context, this.value[:method], args[0], args[1].values, depth + 1)

      if ret.is_a?(JavaObject) || ret.is_a?(Objects::Array)
        ret
      elsif ret.is_a?(Objects::Long)
        JavaObject.new("Ljava/lang/Long;", { number: ret })
      else
        raise "invoke must not be primitive, got #{ret}"
      end
    end

    Loader.load(<<-EOF, context)
      .class public abstract Ljava/util/Timer;

      .method public constructor <init>()V
      .end method
    EOF

    add_ruby_method(context, "Ljava/util/Timer;->schedule(Ljava/util/TimerTask;J)V") do |this, args, context, run_context, depth|
      target = args[0]
      delay = args[1].pair(args[2]).value

      method = MethodLookup.new(context, run_context).lookup_virtual(target, Objects::MethodIdentifier.new("Ljava/util/TimerTask;", "run", "", "V"))
      run(context, run_context, method, target, [], depth + 1)

      #raise "wip"
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

    add_class(context, "Ljava/util/List;")

    add_class(context, "Ljava/util/ArrayList;")
    add_ruby_method(context, "Ljava/util/ArrayList;-><init>()V") do |this, args|
      this.value[:items] = []
    end
    add_ruby_method(context, "Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;") do |this, args|
      JavaObject.new("Ljava/util/Iterator;", { list: this, next_index: 0 })
    end
    add_ruby_method(context, "Ljava/util/ArrayList;->removeAll(Ljava/util/Collection;)Z") do |this, args|
      if args[0].value[:items].empty?
        Objects::False
      else
        pp [this, args]
        raise "wip"
      end
    end
    add_ruby_method(context, "Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z") do |this, args|
      this.value[:items] << args[0]

      Objects::True
    end

    add_ruby_method(context, "Ljava/util/ArrayList;->addAll(Ljava/util/Collection;)Z") do |this, args|
      args[0].value[:items].each do |item|
        this.value[:items] << item
      end

      args[0].value.length > 0 ? Objects::True : Objects::False
    end

    add_ruby_method(context, "Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;", %w[static]) do |this, args|
      JavaObject.new("Ljava/util/ArrayList", { items: args[0].values })
    end

    add_class(context, "Ljava/lang/System;")
    add_ruby_method(context, "Ljava/lang/System;->currentTimeMillis()J", %w[static]) do |this, args|
      now = (Time.now.utc.to_f * 1000).to_i

      Objects::Long.new(now)
    end

    add_class(context, "Ljava/lang/Long;")
    add_ruby_method(context, "Ljava/lang/Long;->longValue()J") do |this, args|
      this.value.fetch(:number)
    end

    add_ruby_method(context, "Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;", %w[static]) do |this, args|
      case args[0]
      when Objects::Integer
        JavaObject.new("Ljava/lang/Long;", { number: args[0].widen })
      else
        raise "wip"
      end
    end

    add_class(context, "Ljava/util/Iterator;", %w[interface])
    add_ruby_method(context, "Ljava/util/Iterator;->hasNext()Z") do |this, args|
      list = this.value[:list]
      index = this.value[:next_index]

      value = index < list.value[:items].length ? 1 : 0
      Objects::Integer.new(value)
    end

    add_ruby_method(context, "Ljava/util/Iterator;->next()Ljava/lang/Object;") do |this, args|
      ret = this.value[:list].value[:items][this.value[:next_index]]
      this.value[:next_index] += 1

      ret
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

  def self.add_class(context, name, modifiers = [])
    Loader.load(<<-EOF, context)
      .class public #{modifiers.join(" ")} #{name}
    EOF
  end

  def self.add_default_constructor(context, name)
    add_ruby_method(context, "#{name}-><init>()V") {}
  end
end
