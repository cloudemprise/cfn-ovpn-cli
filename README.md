# cfn-ovpn-cli

> A virtual private network application in the cloud.

![](./docs/images/cfn-ovpn-cli-sys-overview.png)

A hardened and highly available, multi-client, dual protocol, VPN appliance, accompanied by an isolated Public Key Infrastructure, orchestrated in Cloudformation via the AWS command line interface.

[![Linux](https://img.shields.io/badge/OS-Linux-blue?logo=linux)](https://github.com/cloudemprise/cfn-ovpn-cli)
![Bash](https://img.shields.io/badge/Bash->=v4.0-green?logo=GNU%20bash)
[![jq](https://img.shields.io/badge/jq-v1.6-green.svg)](https://github.com/stedolan/jq)
[![awscli](https://img.shields.io/badge/awscli->=v2.0-green.svg)](https://github.com/aws/aws-cli)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

**Sample CLI Output:**

![](./docs/images/cfn-ovpn-cli-terminal-sample.svg)

## Introduction

cfn-ovpn-cli is a shell script that creates a cloud-based Virtual Private Network (VPN) application together with a isolated Public Key Infrastructure (PKI) Certification Authority, that provides for a secure mobile Wi-Fi roaming solution. The AWS Command Line Interface (AWS CLI) is used to provision and configure various AWS Resources through an assortment of API calls and AWS Cloudformation templates. The templates compose a monolithic hierarchical tree structure of nested stacks and orchestration is achieved in a three-phase stack creation/update process that is promoted via a counter variable.
