#!/usr/bin/env python3
"""Record one read-only call per case against public SOAP services. usage: record_live.py OUTDIR"""
import json, os, re, subprocess, sys, time

ENV11 = 'http://schemas.xmlsoap.org/soap/envelope/'
ENV12 = 'http://www.w3.org/2003/05/soap-envelope'


def env(body, v='1.1', extra=''):
    ns = ENV11 if v == '1.1' else ENV12
    return f'<?xml version="1.0" encoding="UTF-8"?><e:Envelope xmlns:e="{ns}"{extra}><e:Body>{body}</e:Body></e:Envelope>'


ENC = ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:enc="http://schemas.xmlsoap.org/soap/encoding/"'
ES = 'e:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"'
CALC = 'http://www.dneonline.com/calculator.asmx'
CASES = [
 # name, url, version, action, body, extra env attrs, wsdl dir, op, params
 ('calculator-add-11', CALC, '1.1', 'http://tempuri.org/Add', '<Add xmlns="http://tempuri.org/"><intA>2</intA><intB>3</intB></Add>'),
 ('calculator-add-12', CALC, '1.2', 'http://tempuri.org/Add', '<Add xmlns="http://tempuri.org/"><intA>2</intA><intB>3</intB></Add>'),
 ('calculator-divzero-11', CALC, '1.1', 'http://tempuri.org/Divide', '<Divide xmlns="http://tempuri.org/"><intA>1</intA><intB>0</intB></Divide>'),
 ('calculator-divzero-12', CALC, '1.2', 'http://tempuri.org/Divide', '<Divide xmlns="http://tempuri.org/"><intA>1</intA><intB>0</intB></Divide>'),
 ('tempconvert-11', 'https://www.w3schools.com/xml/tempconvert.asmx', '1.1', 'https://www.w3schools.com/xml/CelsiusToFahrenheit', '<CelsiusToFahrenheit xmlns="https://www.w3schools.com/xml/"><Celsius>20</Celsius></CelsiusToFahrenheit>'),
 ('numberconversion-11', 'https://www.dataaccess.com/webservicesserver/NumberConversion.wso', '1.1', '', '<NumberToWords xmlns="http://www.dataaccess.com/webservicesserver/"><ubiNum>500</ubiNum></NumberToWords>'),
 ('numberconversion-12', 'https://www.dataaccess.com/webservicesserver/NumberConversion.wso', '1.2', '', '<NumberToWords xmlns="http://www.dataaccess.com/webservicesserver/"><ubiNum>500</ubiNum></NumberToWords>'),
 ('country-capital', 'http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso', '1.1', '', '<CapitalCity xmlns="http://www.oorsprong.org/websamples.countryinfo"><sCountryISOCode>FR</sCountryISOCode></CapitalCity>'),
 ('country-continents-array', 'http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso', '1.1', '', '<ListOfContinentsByName xmlns="http://www.oorsprong.org/websamples.countryinfo"/>'),
 ('crcind-add', 'https://www.crcind.com/csp/samples/SOAP.Demo.cls', '1.1', 'http://tempuri.org/SOAP.Demo.AddInteger', '<AddInteger xmlns="http://tempuri.org"><Arg1>2</Arg1><Arg2>3</Arg2></AddInteger>'),
 ('crcind-divzero', 'https://www.crcind.com/csp/samples/SOAP.Demo.cls', '1.1', 'http://tempuri.org/SOAP.Demo.DivideInteger', '<DivideInteger xmlns="http://tempuri.org"><Arg1>1</Arg1><Arg2>0</Arg2></DivideInteger>'),
 ('crcind-dataset', 'https://www.crcind.com/csp/samples/SOAP.Demo.cls', '1.1', 'http://tempuri.org/SOAP.Demo.GetDataSetByName', '<GetDataSetByName xmlns="http://tempuri.org"><name>A</name></GetDataSetByName>'),
 ('crcind-person', 'https://www.crcind.com/csp/samples/SOAP.Demo.cls', '1.1', 'http://tempuri.org/SOAP.Demo.FindPerson', '<FindPerson xmlns="http://tempuri.org"><id>1</id></FindPerson>'),
 ('vies-invalid', 'https://ec.europa.eu/taxation_customs/vies/services/checkVatService', '1.1', '', '<checkVat xmlns="urn:ec.europa.eu:taxud:vies:services:checkVat:types"><countryCode>DE</countryCode><vatNumber>000000000</vatNumber></checkVat>'),
 ('ndfd-rpc-encoded', 'https://graphical.weather.gov/xml/SOAP_server/ndfdXMLserver.php', '1.1', 'https://digital.weather.gov/xml/wsdl/ndfdXML.wsdl#LatLonListZipCode', f'<n:LatLonListZipCode xmlns:n="https://digital.weather.gov/xml/wsdl/ndfdXML.wsdl" {ES}><zipCodeList xsi:type="xsd:string">20910</zipCodeList></n:LatLonListZipCode>', ENC),
 ('bcb-rpc-encoded-multiref', 'https://www3.bcb.gov.br/wssgs/services/FachadaWSSGS', '1.1', '', f'<n:getUltimoValorVO xmlns:n="http://publico.ws.casosdeuso.sgs.pec.bcb.gov.br" {ES}><in0 xsi:type="xsd:long">1</in0></n:getUltimoValorVO>', ENC),
 ('smartbear-array', 'http://secure.smartbearsoftware.com/samples/testcomplete14/webservices/Service.asmx', '1.1', 'http://smartbear.com/GetArray', '<GetArray xmlns="http://smartbear.com"/>'),
 ('smartbear-object', 'http://secure.smartbearsoftware.com/samples/testcomplete14/webservices/Service.asmx', '1.1', 'http://smartbear.com/GetSampleObject', '<GetSampleObject xmlns="http://smartbear.com"/>'),
 ('cbr-datetime', 'https://www.cbr.ru/DailyInfoWebServ/DailyInfo.asmx', '1.1', 'http://web.cbr.ru/GetLatestDateTime', '<GetLatestDateTime xmlns="http://web.cbr.ru/"/>'),
 ('cbr-diffgram', 'https://www.cbr.ru/DailyInfoWebServ/DailyInfo.asmx', '1.1', 'http://web.cbr.ru/EnumValutes', '<EnumValutes xmlns="http://web.cbr.ru/"><Seld>false</Seld></EnumValutes>'),
 ('arcgis-defaultmap', 'https://services.arcgisonline.com/arcgis/services/World_Imagery/MapServer', '1.1', '', '<GetDefaultMapName xmlns="http://www.esri.com/schemas/ArcGIS/3.5.0"/>'),
 ('swiss-uid-validate', 'https://www.uid-wse.admin.ch/V5.0/PublicServices.svc', '1.1', 'http://www.uid.admin.ch/xmlns/uid-wse/IPublicServices/ValidateVatNumber', '<ValidateVatNumber xmlns="http://www.uid.admin.ch/xmlns/uid-wse"><vatNumber>CHE-116.281.710</vatNumber></ValidateVatNumber>'),
 ('dilbert', 'http://www.gcomputer.net/webservices/dilbert.asmx', '1.1', 'http://gcomputer.net/webservices/TodaysDilbert', '<TodaysDilbert xmlns="http://gcomputer.net/webservices/"/>'),
 ('ebi-parameters', 'https://www.ebi.ac.uk/Tools/services/soap/clustalo', '1.1', 'urn:GetParameters', '<getParameters xmlns="http://soap.jdispatcher.ebi.ac.uk"/>'),
 ('herong-hello', 'http://www.herongyang.com/Service/Hello_SOAP_11.php', '1.1', 'http://www.herongyang.com/Service/Hello', '<Hello xmlns="http://www.herongyang.com/Service/">World</Hello>'),
 ('eori-invalid', 'https://ec.europa.eu/taxation_customs/dds2/eos/validation/services/validation', '1.1', '', '<ns:validateEORI xmlns:ns="http://eori.ws.eos.dds.s/"><eori>DE000000000</eori></ns:validateEORI>'),
 ('badaction-calculator', CALC, '1.1', 'http://tempuri.org/NoSuchOp', '<NoSuchOp xmlns="http://tempuri.org/"/>'),
 ('malformed-envelope-calculator', CALC, '1.1', 'http://tempuri.org/Add', '<Add xmlns="http://tempuri.org/"><intA>'),
]


def features(body, ctype):
    f = []
    b = body
    t = b.decode('utf-8', 'replace')
    if ENV11 in t: f.append('env:1.1')
    if ENV12 in t: f.append('env:1.2')
    if re.search(r'<[\w:]*Fault[\s>]', t): f.append('fault')
    if 'multiRef' in t: f.append('rpc:multiRef')
    if re.search(r'\bhref="#', t): f.append('rpc:href')
    if re.search(r'xsi:type=', t): f.append('xsi:type')
    if 'arrayType' in t: f.append('soapenc:array')
    if 'diffgr' in t: f.append('dotnet:diffgram')
    if 'xsi:nil' in t: f.append('xsi:nil')
    if '<![CDATA[' in t: f.append('cdata')
    if '&lt;' in t: f.append('escaped-xml-in-text')
    if 'multipart' in (ctype or ''): f.append('multipart')
    if not t.lstrip().startswith(('<', '﻿')): f.append('not-xml')
    if 'html' in (ctype or ''): f.append('html-body')
    if not b: f.append('empty-body')
    m = re.search(r'<([\w.-]+):(?:Body)\b', t)
    if m: f.append('envprefix:' + m.group(1))
    return f


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
res = []
for c in CASES:
    name, url, v, action, body = c[:5]
    extra = c[5] if len(c) > 5 else ''
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    req = env(body, v, extra)
    open(os.path.join(d, 'request.xml'), 'w').write(req)
    hdr = ['-H', f'Content-Type: text/xml; charset=utf-8', '-H', f'SOAPAction: "{action}"'] if v == '1.1' else ['-H', f'Content-Type: application/soap+xml; charset=utf-8; action="{action}"']
    p = subprocess.run(['curl', '-sS', '--max-time', '30', '-A', 'soap-corpus-probe/0.1', '-D', os.path.join(d, 'response.headers'), '-o', os.path.join(d, 'response.body'), '-w', '%{http_code}|%{content_type}|%{time_total}', '--data-binary', '@' + os.path.join(d, 'request.xml'), *hdr, url], capture_output=True, text=True)
    st = p.stdout.split('|')
    code = st[0] if st else '000'
    ct = st[1] if len(st) > 1 else ''
    try:
        raw = open(os.path.join(d, 'response.body'), 'rb').read()
    except FileNotFoundError:
        raw = b''
    feats = features(raw, ct)
    rec = dict(name=name, url=url, version=v, action=action, status=code, content_type=ct, bytes=len(raw), features=feats, err=p.stderr.strip()[:120])
    res.append(rec)
    print(f"{name:32} {code:4} {ct[:38]:38} {len(raw):7}  {' '.join(feats)} {rec['err']}")
    time.sleep(0.4)
json.dump(res, open(os.path.join(out, 'index.json'), 'w'), indent=1)
