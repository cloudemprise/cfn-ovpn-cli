# cfn-ovpn-cli

> A virtual private network application in the cloud.

![](./docs/images/cfn-ovpn-cli-sys-overview.png)

A hardened and highly available, multi-client, dual protocol, VPN appliance, accompanied by an isolated Public Key Infrastructure framework, orchestrated in Cloudformation via the AWS command line interface.

[![Linux](https://img.shields.io/badge/OS-Linux-blue?logo=linux)](https://github.com/cloudemprise/cfn-ovpn-cli)
![Bash](https://img.shields.io/badge/Bash->=v4.0-green?logo=GNU%20bash)
[![jq](https://img.shields.io/badge/jq-v1.6-green.svg)](https://github.com/stedolan/jq)
[![awscli](https://img.shields.io/badge/awscli->=v2.0-green.svg)](https://github.com/aws/aws-cli)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

**Sample CLI Output:**

![](./docs/images/cfn-ovpn-cli-terminal-sample.svg)

**Full Demo CLI Output can be found Here**

Table of Contents
=================

- [Introduction](#introduction)
- [OpenVPN](#openvpn)
- [Pulic Key Infrastructure](#public-key-infrastructure)
- [Cloudformation](#cloudformation)
- [Firewall](#firewall)
- [Hardening](#hardening)


## Prerequisites

- aws account.
- ssh key in stack build region.
- route 53 hosted zone.
- jq version 1.6
- awscli version 2
- bash > version 4

## Introduction

cfn-ovpn-cli is a shell script that creates a cloud-based Virtual Private Network (VPN) application together with a isolated Public Key Infrastructure (PKI) Certification Authority, that provides for a secure mobile Wi-Fi roaming solution. The AWS Command Line Interface (AWS CLI) is used to provision and configure various AWS Resources through an assortment of API calls and AWS Cloudformation templates. The templates compose a monolithic hierarchical tree structure of nested stacks and orchestration is achieved in a three-phase stack creation/update process that is promoted via a counter variable.

## OpenVPN


OpenVPN is a popular VPN daemon that is remarkably flexible and decidedly simple to setup. It is particularly suitable for small deployments and uses the TLS protocol to secure its connections.  It derives its cryptographic capabilities from the OpenSSL library but can also be compiled with [Mbed TLS](https://tls.mbed.org) as its cryptographic backend, ensuring the independence of the underlying encryption libraries. 

OpenVPN operates by using a virtual network adapter as an interface between user space and kernel space and listens for client connections on both UDP and TCP. OpenVPN defines the concept of a control channel and a data channel, both of which are encrypted and secured separately but pass over the same protocol connection. The control channel is encrypted and secured using TLS while the data channel is encrypted using a chosen block cipher.

cfn-ovpn-cli uses the following parameters:

|   | Control Channel | Data Channel
| ----  |:--- | ---
| Encryption | secp521r1 | AES-256-GCM
| Authentication | sha512 | sha512


## Public Key Infrastructure

A secure VPN requires some form of authentication and this here involves two components:

1. Client/Server Authentication. This ensures that the server and clients are indeed communicating with authorized known entities and not a spoofed fake user/host.

2. A method of hashing each data packet within the system is also established. By authenticating each data packet, the system does not waste cpu cycles decrypting packets that do not meet the authentication rules. Thus preventing many types of attack vectors.

A system that uses key-based authentication requires a Public Key Infrastructure (PKI). In basic terms, a PKI consists of the following:

* A public master Certificate Authority (CA) certificate and a private key.
* A separate public certificate and private key pair for the server.
* A separate public certificate and private key pair for each client.

A very convienient mechanism for creating a PKI is to use the [Easy-RSA](https://github.com/OpenVPN/easy-rsa) utility. Easy-RSA is a framework for managing X.509 PKI. It is based around the concept of a trusted root signing authority and the backend is comprised of the OpenSSL cryptographic library.

cfn-ovpn-cli builds two interrelated PKIs on hardened virtual linux servers within a VPC in the AWS Cloud. A trusted root CA is created within the isolated private subnet, only accessible via a Bastion Host and used exclusively to sign certificate requests. A second PKI is created on the OpenVPN application server itself which resides within the public subnet of the VPC. Here the server as well as the client certificates and private keys are generated. Requests and signed certificates are automaticaly exchanged between these two systems by way of Cloudformation Stack Updates. This is described in more detail in the Cloudformation section of this below but hinges around evoking the ec2 create-image API and its associated Launch Template. The CA is further constrained by a passphrase that is securely stored and retrived via the AWS System Manager Parameter Store secrets management protocol. The elliptical curve secp521r1 key exchange cipher was chosen for smaller key size equivalence and faster execution performance.


## Cloudformation

* Infrastructure as code.
* AWS CloudFormation provisions and configures resources and sorts out dependancies.
* AWS CloudFormation create and manage AWS infrastructure deployments predictably and repeatedly. 
* AWS CloudFormation resources and dependencies are declared in a template file that describes all the AWS resources.  A template describes all of your resources and their properties. 
* The template defines a collection of resources as a single unit called a stack.
* AWS CloudFormation is a service that helps you model and set up your Amazon Web Services resources.
* Simplify Infrastructure Management
* you easily manage a collection of resources as a single unit.
* Quickly Replicate Your Infrastructure in another region or account.
* set up your resources consistently and repeatedly.
* Easily Control and Track Changes to Your Infrastructure
* you can use a version control system with your templates.

## Firewall

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla imperdiet urna nulla, eget faucibus est sagittis eget. Curabitur nisi elit, placerat sed posuere eget, faucibus egestas risus. Nam interdum ac quam at dictum. Aenean blandit lobortis urna. In dapibus blandit ante ut rhoncus. Sed semper, nisl eu lobortis viverra, lorem odio facilisis dui, et porta neque lectus at velit. Sed a scelerisque odio. Integer placerat tempus lobortis. Curabitur efficitur sed libero vitae lacinia. Ut laoreet sapien ex, sit amet volutpat ex fermentum eu. Fusce pulvinar lacinia velit quis aliquam. Ut rutrum molestie elit, vitae rutrum augue malesuada vitae. Aliquam erat volutpat. Morbi a nunc quis dolor lobortis aliquet. Nullam diam lorem, pulvinar sed mattis quis, viverra sit amet odio. Curabitur posuere arcu ex. 

## Hardening

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla imperdiet urna nulla, eget faucibus est sagittis eget. Curabitur nisi elit, placerat sed posuere eget, faucibus egestas risus. Nam interdum ac quam at dictum. Aenean blandit lobortis urna. In dapibus blandit ante ut rhoncus. Sed semper, nisl eu lobortis viverra, lorem odio facilisis dui, et porta neque lectus at velit. Sed a scelerisque odio. Integer placerat tempus lobortis. Curabitur efficitur sed libero vitae lacinia. Ut laoreet sapien ex, sit amet volutpat ex fermentum eu. Fusce pulvinar lacinia velit quis aliquam. Ut rutrum molestie elit, vitae rutrum augue malesuada vitae. Aliquam erat volutpat. Morbi a nunc quis dolor lobortis aliquet. Nullam diam lorem, pulvinar sed mattis quis, viverra sit amet odio. Curabitur posuere arcu ex. 
