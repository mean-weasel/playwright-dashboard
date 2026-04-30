#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
  let x = Double(CommandLine.arguments[1]),
  let y = Double(CommandLine.arguments[2])
else {
  fputs("Usage: post_pointer_events.swift <x> <y>\n", stderr)
  exit(2)
}

let screenHeight = NSScreen.screens.first?.frame.height ?? 0
let eventY = screenHeight > 0 ? screenHeight - y : y
let point = CGPoint(x: x, y: eventY)
let source = CGEventSource(stateID: .hidSystemState)

func post(_ event: CGEvent?) {
  event?.post(tap: .cghidEventTap)
  usleep(120_000)
}

let moved = CGEvent(
  mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
let pressed = CGEvent(
  mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point,
  mouseButton: .left)
pressed?.setIntegerValueField(.mouseEventClickState, value: 1)
let released = CGEvent(
  mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
released?.setIntegerValueField(.mouseEventClickState, value: 1)
let wheel = CGEvent(
  scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: -6, wheel2: 0, wheel3: 0)
wheel?.location = point

post(moved)
post(pressed)
post(released)
post(wheel)
