defmodule Soap.Conformance.Support do
  @moduledoc "Shared fixtures and helpers for the conformance layers."

  alias Soap.Conformance.Xml

  @corpus Path.expand("../../corpus", __DIR__)

  def corpus_path(relative \\ ""), do: Path.join(@corpus, relative)

  def manifest do
    corpus_path("manifest.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("entries")
  end

  @doc "Limits a generated test name, keeping it unique with a short hash."
  def test_label(text) do
    short = String.slice(text, 0, 90)
    if short == text, do: text, else: "#{short}~#{:erlang.phash2(text, 100_000)}"
  end

  @doc "Builds a param node. Takes a name and value, with optional attributes."
  def node(name, value, attrs \\ %{}), do: {to_string(name), attrs, value}

  @doc "A small document/literal WSDL. Options change the parts that vary between tests."
  def wsdl(opts \\ []) do
    pfx = opts[:schema_prefix] || "xsd"
    soap_uri = opts[:soap_uri] || "http://schemas.xmlsoap.org/wsdl/soap/"
    fields = opts[:fields] || ~s(<#{pfx}:element name="zeta" type="#{pfx}:string"/><#{pfx}:element name="alpha" type="#{pfx}:string"/>)
    element_name = opts[:element_name] || "Pay"
    type_name = opts[:type_name] || element_name
    action = Keyword.get(opts, :action, "urn:t/Pay")
    endpoint = opts[:endpoint] || "http://svc.example/endpoint"
    input_extra = opts[:input_extra] || ""
    root_extra = opts[:root_extra] || ""
    imports = opts[:imports] || ""
    extra_types = opts[:extra_types] || ""

    """
    <wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:soap="#{soap_uri}" xmlns:#{pfx}="http://www.w3.org/2001/XMLSchema" xmlns:tns="urn:t" #{root_extra} targetNamespace="urn:t">
      <wsdl:types><#{pfx}:schema targetNamespace="urn:t" elementFormDefault="qualified">#{imports}
        <#{pfx}:element name="#{element_name}" type="tns:#{type_name}"/>
        <#{pfx}:element name="PayOut" type="tns:PayOutT"/>
        <#{pfx}:complexType name="#{type_name}"><#{pfx}:sequence>#{fields}</#{pfx}:sequence></#{pfx}:complexType>
        <#{pfx}:complexType name="PayOutT"><#{pfx}:sequence><#{pfx}:element name="result" type="#{pfx}:string"/><#{pfx}:element name="item" type="#{pfx}:string" minOccurs="0" maxOccurs="unbounded"/></#{pfx}:sequence></#{pfx}:complexType>
        #{extra_types}
      </#{pfx}:schema></wsdl:types>
      <wsdl:message name="In"><wsdl:part name="body" element="tns:#{element_name}"/></wsdl:message>
      <wsdl:message name="Out"><wsdl:part name="body" element="tns:PayOut"/></wsdl:message>
      <wsdl:portType name="PT"><wsdl:operation name="Pay"><wsdl:input message="tns:In"/><wsdl:output message="tns:Out"/></wsdl:operation></wsdl:portType>
      <wsdl:binding name="B" type="tns:PT"><soap:binding style="document" transport="http://schemas.xmlsoap.org/soap/http"/>
        <wsdl:operation name="Pay"><soap:operation soapAction="#{action}"/><wsdl:input>#{input_extra}<soap:body use="literal"/></wsdl:input><wsdl:output><soap:body use="literal"/></wsdl:output></wsdl:operation>
      </wsdl:binding>
      <wsdl:service name="S"><wsdl:port name="P" binding="tns:B"><soap:address location="#{endpoint}"/></wsdl:port></wsdl:service>
    </wsdl:definitions>
    """
  end

  def soap11(inner), do: ~s(<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>#{inner}</s:Body></s:Envelope>)
  def soap12(inner), do: ~s(<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"><e:Body>#{inner}</e:Body></e:Envelope>)

  def fault11(code \\ "s:Server", message \\ "boom") do
    soap11("<s:Fault><faultcode>#{code}</faultcode><faultstring>#{message}</faultstring></s:Fault>")
  end

  def pay_reply(result \\ "done"), do: soap11(~s(<PayOut xmlns="urn:t"><result>#{result}</result></PayOut>))

  @doc "Parses a request body and returns the normalized children of its SOAP Body."
  def request_body(%{body: body}) do
    with {:ok, doc} <- Xml.parse(body), do: Xml.body_children(doc)
  end

  @doc "Every scalar in a decoded result, as strings."
  def leaves(term) when is_map(term) and not is_struct(term), do: term |> Map.values() |> Enum.flat_map(&leaves/1)
  def leaves(term) when is_list(term), do: Enum.flat_map(term, &leaves/1)
  def leaves({_key, value}), do: leaves(value)
  def leaves(nil), do: []
  def leaves(term) when is_binary(term), do: [term]
  def leaves(term) when is_struct(term), do: [to_string(term)]
  def leaves(term), do: [to_string(term)]

  @doc "All keys in a decoded result at any depth, as strings."
  def keys(term) when is_map(term) and not is_struct(term) do
    Enum.flat_map(term, fn {k, v} -> [to_string(k) | keys(v)] end)
  end

  def keys(term) when is_list(term) do
    Enum.flat_map(term, fn
      {k, v} -> [to_string(k) | keys(v)]
      other -> keys(other)
    end)
  end

  def keys(_term), do: []

  @doc "All values under a key with this local name, whatever its prefix."
  def values_at(term, name) when is_map(term) and not is_struct(term) do
    Enum.flat_map(term, fn {k, v} -> matching(k, v, name) ++ values_at(v, name) end)
  end

  def values_at(term, name) when is_list(term) do
    Enum.flat_map(term, fn
      {k, v} -> matching(k, v, name) ++ values_at(v, name)
      other -> values_at(other, name)
    end)
  end

  def values_at(_term, _name), do: []

  defp matching(key, value, name) do
    if key |> to_string() |> String.split(":") |> List.last() == name, do: [value], else: []
  end
end
