defmodule OperationError do
  @moduledoc """
  Defines an exception that handles an inaccessible wsdl operations.
  """

  defexception [:message]

  def exception(soap_operation) do
    msg =
      "#{soap_operation} operation is not described in this wsdl file. Use SOAP.operations(wsdl) to list all available operations"

    %OperationError{message: msg}
  end
end
