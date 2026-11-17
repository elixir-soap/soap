defmodule Soap.Schema.ElementDecl do
  @moduledoc "An `xsd:element` declaration or reference."
  defstruct [
    :name,
    :ns,
    :ref,
    :type,
    :inline,
    :default,
    :fixed,
    :substitution_group,
    min: 1,
    max: 1,
    nillable: false,
    abstract: false,
    global?: false
  ]

  @type t :: %__MODULE__{}
end

defmodule Soap.Schema.AttributeDecl do
  @moduledoc "An `xsd:attribute` declaration or reference."
  defstruct [:name, :ns, :ref, :type, :inline, :default, :fixed, :array_type, use: "optional"]

  @type t :: %__MODULE__{}
end

defmodule Soap.Schema.AttributeGroupRef do
  @moduledoc "A reference to an `xsd:attributeGroup`."
  defstruct [:ref]

  @type t :: %__MODULE__{}
end

defmodule Soap.Schema.ComplexType do
  @moduledoc """
  An `xsd:complexType`.

  `content` is the type's own particle. With a `base`, `derivation` says how it relates
  to the base type. `array_type` is the item type of a `soapenc:Array` restriction.
  """
  defstruct [
    :name,
    :ns,
    :base,
    :derivation,
    :content,
    :array_type,
    attributes: [],
    any_attribute: false,
    simple_content: false,
    abstract: false,
    mixed: false
  ]

  @type t :: %__MODULE__{}
end

defmodule Soap.Schema.SimpleType do
  @moduledoc "An `xsd:simpleType`: a restriction, a list or a union."
  defstruct [
    :name,
    :ns,
    :base,
    :item_type,
    :inline_item,
    variety: :atomic,
    member_types: [],
    inline_members: [],
    enumeration: [],
    patterns: [],
    facets: %{}
  ]

  @type t :: %__MODULE__{}
end

defmodule Soap.Schema.Group do
  @moduledoc "A `sequence`, `choice` or `all` particle."
  defstruct [:kind, min: 1, max: 1, items: []]

  @type t :: %__MODULE__{}
end

defmodule Soap.Schema.GroupRef do
  @moduledoc "A reference to a named `xsd:group`."
  defstruct [:ref, min: 1, max: 1]

  @type t :: %__MODULE__{}
end

defmodule Soap.Schema.Any do
  @moduledoc "An `xsd:any` wildcard."
  defstruct [:namespace, :process_contents, min: 1, max: 1]

  @type t :: %__MODULE__{}
end
