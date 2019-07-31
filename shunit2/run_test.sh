#!/bin/bash

# First example from https://github.com/kward/shunit2

testEquality()
{
    assertEquals 1 1
}

# load shunit2
. /usr/local/bin/shunit2
