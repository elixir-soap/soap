defmodule Soap.Request.Options do
  defstruct [:headers, :body]
  import XmlBuilder
  @moduledoc """
  Documentation for Soap.Request.Options.
  """

  def init_model(locals, params) do
    %Soap.Request.Options{
      headers: base_headers(locals[:soap_action]),
      body: prepare_body(params)
    }
  end


  # generate("inCommonParms", [{"userID", "WSPB"}, {"branchNumber", "0000"}, {"externalSystemCode", "P2B0"}, {"externalUserCode", "WSPB"}])
  # =>
  # <?xml version="1.0" encoding="UTF-8"?>
  # <inCommonParms>
  #   <userID>WSPB</userID>
  #   <branchNumber>0000</branchNumber>
  #   <externalSystemCode>P2B0</externalSystemCode>
  #   <externalUserCode>WSPB</externalUserCode>
  # </inCommonParms>
  defp prepare_body(params) do
    params |> generate
  end

  defp base_headers(soap_action) do
    [{"SOAPAction", to_string(soap_action)},
     {"Content-Type", "text/xml;charset=UTF-8"}]
  end
end
