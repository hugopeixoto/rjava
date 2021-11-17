require_relative './loader'

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
        const-wide v0, 0x0L
        return-wide v0
      .end method
    EOF
  end
end
