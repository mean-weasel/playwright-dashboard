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

guard let screen = NSScreen.screens.first else {
  fputs("Error: No screens available. Cannot compute event coordinates.\n", stderr)
  exit(1)
}

// Convert from top-left (accessibility/screen coordinates) to bottom-left (Quartz CGEvent coordinates).
let screenHeight = screen.frame.height
let eventY = screenHeight - y
let point = CGPoint(x: x, y: eventY)
let source = CGEventSource(stateID: .hidSystemState)

func post(_ event: CGEvent?) {
  guard let event else {
    fputs("Error: CGEvent creation returned nil. Check Accessibility/Input Monitoring permissions.\n", stderr)
    exit(1)
  }
  event.post(tap: .cghidEventTap)
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
