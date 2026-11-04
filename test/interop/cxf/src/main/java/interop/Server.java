package interop;

import jakarta.activation.DataHandler;
import jakarta.jws.WebMethod;
import jakarta.jws.WebParam;
import jakarta.jws.WebResult;
import jakarta.jws.WebService;
import jakarta.jws.soap.SOAPBinding;
import jakarta.xml.bind.annotation.XmlMimeType;
import jakarta.xml.ws.soap.SOAPFaultException;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.security.auth.callback.CallbackHandler;
import org.apache.cxf.jaxws.JaxWsServerFactoryBean;
import org.apache.cxf.ws.security.wss4j.WSS4JInInterceptor;
import org.apache.wss4j.common.ext.WSPasswordCallback;
import org.apache.wss4j.dom.handler.WSHandlerConstants;

/** Real SOAP services for the interop layer: document, rpc, SOAP 1.2, MTOM and WS-Security. */
public class Server {
  public static class Item {
    public String name;
    public int quantity;
    public double price;
    public boolean urgent;
    public List<String> tags = new ArrayList<>();
  }

  @WebService(targetNamespace = "urn:cxf", name = "Doc", serviceName = "DocService")
  public static class DocService {
    @WebMethod
    @WebResult(name = "item")
    public Item echoItem(@WebParam(name = "item") Item item) {
      item.quantity = item.quantity + 1;
      return item;
    }

    @WebMethod
    @WebResult(name = "result")
    public String greet(@WebParam(name = "name") String name) {
      return "Hello, " + name;
    }

    @WebMethod
    @WebResult(name = "result")
    public String fail(@WebParam(name = "message") String message) throws Exception {
      throw new IllegalStateException(message);
    }
  }

  @WebService(targetNamespace = "urn:cxf", name = "Rpc", serviceName = "RpcService")
  @SOAPBinding(style = SOAPBinding.Style.RPC)
  public static class RpcService {
    @WebMethod
    @WebResult(name = "sum")
    public int add(@WebParam(name = "a") int a, @WebParam(name = "b") int b) {
      return a + b;
    }
  }

  @WebService(targetNamespace = "urn:cxf", name = "Files", serviceName = "FilesService")
  public static class FilesService {
    /** Returns the bytes reversed, so a test can tell the server really read them. */
    @WebMethod
    @WebResult(name = "data")
    @XmlMimeType("application/octet-stream")
    public DataHandler reverse(@WebParam(name = "data") @XmlMimeType("application/octet-stream") DataHandler data)
        throws Exception {
      byte[] bytes = readAll(data);
      byte[] reversed = new byte[bytes.length];
      for (int i = 0; i < bytes.length; i++) {
        reversed[i] = bytes[bytes.length - 1 - i];
      }
      return new DataHandler(new jakarta.mail.util.ByteArrayDataSource(reversed, "application/octet-stream"));
    }

    private static byte[] readAll(DataHandler handler) throws Exception {
      try (InputStream in = handler.getInputStream(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
        in.transferTo(out);
        return out.toByteArray();
      }
    }
  }

  @WebService(targetNamespace = "urn:cxf", name = "Secure", serviceName = "SecureService")
  public static class SecureService {
    @WebMethod
    @WebResult(name = "result")
    public String whoAmI() {
      return "authenticated";
    }
  }

  private static void publish(String path, Object service, boolean soap12, boolean mtom, Map<String, Object> security) {
    JaxWsServerFactoryBean factory = new JaxWsServerFactoryBean();
    factory.setServiceClass(service.getClass());
    factory.setServiceBean(service);
    factory.setAddress("http://0.0.0.0:8080" + path);
    Map<String, Object> properties = new HashMap<>();
    if (mtom) {
      properties.put("mtom-enabled", Boolean.TRUE);
    }
    factory.setProperties(properties);
    if (soap12) {
      factory.setBindingId("http://schemas.xmlsoap.org/wsdl/soap12/");
    }
    if (security != null) {
      factory.getInInterceptors().add(new WSS4JInInterceptor(security));
    }
    factory.create();
  }

  private static Map<String, Object> usernameToken(String passwordType) {
    CallbackHandler passwords = callbacks -> {
      for (var callback : callbacks) {
        if (callback instanceof WSPasswordCallback password && "ann".equals(password.getIdentifier())) {
          password.setPassword("secret");
        }
      }
    };
    Map<String, Object> security = new HashMap<>();
    security.put(WSHandlerConstants.ACTION, WSHandlerConstants.USERNAME_TOKEN);
    security.put(WSHandlerConstants.PASSWORD_TYPE, passwordType);
    security.put(WSHandlerConstants.PW_CALLBACK_REF, passwords);
    return security;
  }

  public static void main(String[] args) throws Exception {
    publish("/doc", new DocService(), false, false, null);
    publish("/doc12", new DocService(), true, false, null);
    publish("/rpc", new RpcService(), false, false, null);
    publish("/files", new FilesService(), false, true, null);
    publish("/files12", new FilesService(), true, true, null);
    publish("/secure", new SecureService(), false, false, usernameToken("PasswordText"));
    publish("/secure-digest", new SecureService(), false, false, usernameToken("PasswordDigest"));
    System.out.println("listening");
    Thread.currentThread().join();
  }
}
