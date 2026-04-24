#!/bin/bash

systemctl list-units container@\* | grep container@ | sed -r 's/.*container@(\S*)\.service.*/\1/'
