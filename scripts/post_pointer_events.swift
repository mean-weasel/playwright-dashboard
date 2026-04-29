#!/usr/bin/env swift

import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
  let x = Double(CommandLine.arguments[1]),
  let y = Double(CommandLine.arguments[2])
else {
  fputs("Usage: post_pointer_events.swift <x> <y>\n", stderr)
  exit(2)
}

let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)

func post(_ event: CGEvent?) {
  event?.post(tap: .cghidEventTap)
  usleep(120_000)
}

post(
  CGEvent(
    mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left
  ))
post(
  CGEvent(
    mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point,
    mouseButton: .left))
post(
  CGEvent(
    mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point,
    mouseButton: .left))
post(
  CGEvent(
    scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: -6, wheel2: 0, wheel3: 0))
