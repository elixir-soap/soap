<?php
// An rpc/encoded service: PHP's SoapServer is one of the few still producing this style.
ini_set('soap.wsdl_cache_enabled', '0');

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    header('Content-Type: text/xml');
    readfile(__DIR__ . '/rpc.wsdl');
    exit;
}

class RpcService
{
    public function echoString($value) { return $value; }

    public function add($a, $b) { return $a + $b; }

    public function echoFlag($flag) { return !$flag; }

    public function echoStrings($values) { return array_reverse($values); }

    public function getOrder($id)
    {
        $customer = new stdClass();
        $customer->name = 'Ann';
        $order = new stdClass();
        $order->id = $id;
        $order->total = 12.5;
        $order->paid = true;
        $order->lines = ['a', 'b'];
        // Referring to one object twice makes PHP send an href.
        $order->buyer = $customer;
        $order->payer = $customer;
        return $order;
    }

    public function fail($message) { throw new SoapFault('Server', $message); }
}

$server = new SoapServer(__DIR__ . '/rpc.wsdl', ['cache_wsdl' => WSDL_CACHE_NONE]);
$server->setClass('RpcService');
$server->handle();
