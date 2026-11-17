// A document/literal service on node-soap, with optional WS-Security checking.
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const soap = require('soap');

const USER = 'ann';
const PASSWORD = 'secret';

function checkToken(security) {
  const token = security && security.UsernameToken;
  if (!token || token.Username !== USER) return false;

  const password = token.Password;
  const type = password.attributes && password.attributes.Type;
  const text = password.$value;

  if (type && type.endsWith('#PasswordDigest')) {
    const nonce = Buffer.from(token.Nonce.$value, 'base64');
    const created = Buffer.from(token.Created);
    const digest = crypto.createHash('sha1').update(Buffer.concat([nonce, created, Buffer.from(PASSWORD)])).digest('base64');
    return digest === text;
  }
  return text === PASSWORD;
}

const operations = {
  Echo(args) {
    return { message: args.message, count: args.count, tags: args.tags, nested: args.nested };
  },
  Secure(args, _callback, headers) {
    const security = headers && headers.Security;
    if (!checkToken(security)) {
      throw { Fault: { Code: { Value: 'soap:Sender' }, Reason: { Text: 'Unauthorized' } } };
    }
    return { message: 'hello ' + security.UsernameToken.Username };
  },
};

const services = { DocService: { DocPort: operations } };

const server = http.createServer((_req, res) => {
  res.statusCode = 404;
  res.end();
});

server.listen(8080, '0.0.0.0', () => {
  soap.listen(server, '/doc', services, fs.readFileSync('doc.wsdl', 'utf8'));
  console.log('listening');
});
