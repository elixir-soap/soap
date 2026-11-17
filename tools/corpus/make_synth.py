#!/usr/bin/env python3
"""Write hand-made fixtures for variants the harvest did not cover. usage: make_synth.py DIR"""
import os, sys

root = sys.argv[1]
N = 'xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/" xmlns:soap12="http://schemas.xmlsoap.org/wsdl/soap12/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:tns="urn:s" targetNamespace="urn:s"'
BIND = 'transport="http://schemas.xmlsoap.org/soap/http"'


def w(rel, text, enc='utf-8'):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding=enc, newline='').write(text)


def doc(types, msgs, pt, binding, svc='<wsdl:service name="S"><wsdl:port name="P" binding="tns:B"><soap:address location="http://localhost:9/s"/></wsdl:port></wsdl:service>', extra=''):
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<wsdl:definitions {N}{extra}>\n<wsdl:types><xsd:schema targetNamespace="urn:s" elementFormDefault="qualified">{types}</xsd:schema></wsdl:types>\n{msgs}\n<wsdl:portType name="PT">{pt}</wsdl:portType>\n<wsdl:binding name="B" type="tns:PT"><soap:binding style="document" {BIND}/>{binding}</wsdl:binding>\n{svc}\n</wsdl:definitions>\n'


def bop(name, action='urn:s/x', input_name=None):
    i = f' name="{input_name}"' if input_name else ''
    return f'<wsdl:operation name="{name}"><soap:operation soapAction="{action}"/><wsdl:input{i}><soap:body use="literal"/></wsdl:input><wsdl:output><soap:body use="literal"/></wsdl:output></wsdl:operation>'


SIMPLE_T = '<xsd:element name="Ping"><xsd:complexType><xsd:sequence><xsd:element name="v" type="xsd:string"/></xsd:sequence></xsd:complexType></xsd:element><xsd:element name="PingR" type="xsd:string"/>'
SIMPLE_M = '<wsdl:message name="In"><wsdl:part name="p" element="tns:Ping"/></wsdl:message><wsdl:message name="Out"><wsdl:part name="p" element="tns:PingR"/></wsdl:message>'
SIMPLE_P = '<wsdl:operation name="Ping"><wsdl:input message="tns:In"/><wsdl:output message="tns:Out"/></wsdl:operation>'

# Overloaded operation names, told apart by input name (WSDL 1.1 allows this; WS-I forbids it)
w('wsdl/overloaded-operations.wsdl', doc(
    SIMPLE_T + '<xsd:element name="PingB" type="xsd:int"/>',
    SIMPLE_M + '<wsdl:message name="InB"><wsdl:part name="p" element="tns:PingB"/></wsdl:message>',
    '<wsdl:operation name="Ping"><wsdl:input name="ByText" message="tns:In"/><wsdl:output message="tns:Out"/></wsdl:operation><wsdl:operation name="Ping"><wsdl:input name="ByNumber" message="tns:InB"/><wsdl:output message="tns:Out"/></wsdl:operation>',
    bop('Ping', 'urn:s/text', 'ByText') + bop('Ping', 'urn:s/number', 'ByNumber')))

# UTF-16 with BOM
w('wsdl/utf16-encoded.wsdl', '﻿' + doc(SIMPLE_T, SIMPLE_M, SIMPLE_P, bop('Ping')).replace('encoding="UTF-8"', 'encoding="UTF-16"'), enc='utf-16-le')

# substitutionGroup, abstract element and type, inline
w('wsdl/substitution-group-inline.wsdl', doc(
    '<xsd:element name="Shape" type="tns:ShapeT" abstract="true"/><xsd:element name="Circle" type="tns:CircleT" substitutionGroup="tns:Shape"/>'
    '<xsd:complexType name="ShapeT" abstract="true"><xsd:sequence><xsd:element name="id" type="xsd:int"/></xsd:sequence></xsd:complexType>'
    '<xsd:complexType name="CircleT"><xsd:complexContent><xsd:extension base="tns:ShapeT"><xsd:sequence><xsd:element name="r" type="xsd:double"/></xsd:sequence></xsd:extension></xsd:complexContent></xsd:complexType>'
    '<xsd:element name="Draw"><xsd:complexType><xsd:sequence><xsd:element ref="tns:Shape" maxOccurs="unbounded"/></xsd:sequence></xsd:complexType></xsd:element><xsd:element name="DrawR" type="xsd:boolean"/>',
    '<wsdl:message name="In"><wsdl:part name="p" element="tns:Draw"/></wsdl:message><wsdl:message name="Out"><wsdl:part name="p" element="tns:DrawR"/></wsdl:message>',
    '<wsdl:operation name="Draw"><wsdl:input message="tns:In"/><wsdl:output message="tns:Out"/></wsdl:operation>', bop('Draw')))

# Same operation on 1.1 and 1.2 ports with different actions, and two services
w('wsdl/divergent-bindings.wsdl', f'''<?xml version="1.0" encoding="UTF-8"?>
<wsdl:definitions {N}>
<wsdl:types><xsd:schema targetNamespace="urn:s" elementFormDefault="qualified">{SIMPLE_T}</xsd:schema></wsdl:types>
{SIMPLE_M}
<wsdl:portType name="PT">{SIMPLE_P}</wsdl:portType>
<wsdl:binding name="B11" type="tns:PT"><soap:binding style="document" {BIND}/><wsdl:operation name="Ping"><soap:operation soapAction="urn:s/v11"/><wsdl:input><soap:body use="literal"/></wsdl:input><wsdl:output><soap:body use="literal"/></wsdl:output></wsdl:operation></wsdl:binding>
<wsdl:binding name="B12" type="tns:PT"><soap12:binding style="document" {BIND}/><wsdl:operation name="Ping"><soap12:operation soapAction="urn:s/v12" soapActionRequired="true"/><wsdl:input><soap12:body use="literal"/></wsdl:input><wsdl:output><soap12:body use="literal"/></wsdl:output></wsdl:operation></wsdl:binding>
<wsdl:service name="A"><wsdl:port name="A11" binding="tns:B11"><soap:address location="http://localhost:9/a11"/></wsdl:port><wsdl:port name="A12" binding="tns:B12"><soap12:address location="http://localhost:9/a12"/></wsdl:port></wsdl:service>
<wsdl:service name="Z"><wsdl:port name="Z11" binding="tns:B11"><soap:address location="http://localhost:9/z11"/></wsdl:port></wsdl:service>
</wsdl:definitions>
''')

# Import cycles must terminate
w('wsdl/circular-wsdl/a.wsdl', f'<?xml version="1.0"?>\n<wsdl:definitions {N}><wsdl:import namespace="urn:s" location="b.wsdl"/><wsdl:message name="A"/></wsdl:definitions>\n')
w('wsdl/circular-wsdl/b.wsdl', f'<?xml version="1.0"?>\n<wsdl:definitions {N}><wsdl:import namespace="urn:s" location="a.wsdl"/><wsdl:message name="B"/></wsdl:definitions>\n')
w('wsdl/circular-xsd/service.wsdl', doc('<xsd:import namespace="urn:x" schemaLocation="x.xsd"/>' + SIMPLE_T, SIMPLE_M, SIMPLE_P, bop('Ping')))
w('wsdl/circular-xsd/x.xsd', '<?xml version="1.0"?>\n<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:x"><xsd:import namespace="urn:y" schemaLocation="y.xsd"/><xsd:element name="X" type="xsd:string"/></xsd:schema>\n')
w('wsdl/circular-xsd/y.xsd', '<?xml version="1.0"?>\n<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:y"><xsd:import namespace="urn:x" schemaLocation="x.xsd"/><xsd:element name="Y" type="xsd:string"/></xsd:schema>\n')

# Security negatives: a client must reject these, or refuse to follow them by default
w('negative/xxe-external-entity.wsdl', f'<?xml version="1.0"?>\n<!DOCTYPE wsdl:definitions [<!ENTITY x SYSTEM "file:///etc/passwd">]>\n<wsdl:definitions {N}><wsdl:documentation>&x;</wsdl:documentation></wsdl:definitions>\n')
ents = '<!ENTITY a0 "aaaaaaaaaa">' + ''.join(f'<!ENTITY a{i} "{("&a%d;" % (i-1))*10}">' for i in range(1, 10))
w('negative/entity-expansion-bomb.wsdl', f'<?xml version="1.0"?>\n<!DOCTYPE wsdl:definitions [{ents}]>\n<wsdl:definitions {N}><wsdl:documentation>&a9;</wsdl:documentation></wsdl:definitions>\n')
w('negative/ssrf-schema-location.wsdl', doc('<xsd:import namespace="urn:a" schemaLocation="http://169.254.169.254/latest/meta-data/"/><xsd:import namespace="urn:b" schemaLocation="file:///etc/passwd"/>' + SIMPLE_T, SIMPLE_M, SIMPLE_P, bop('Ping')))
w('negative/path-traversal-import.wsdl', doc('<xsd:import namespace="urn:a" schemaLocation="../../../../../../../../etc/passwd"/>' + SIMPLE_T, SIMPLE_M, SIMPLE_P, bop('Ping')))
print('ok')
