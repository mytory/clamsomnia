import AppKit

enum CatIcon {
    static func image(isAwake: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            context.imageInterpolation = .high
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let head = NSBezierPath()
            head.lineWidth = 1.35
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.move(to: NSPoint(x: 2.2, y: 2.6))
            head.line(to: NSPoint(x: 2.2, y: 8.2))
            head.line(to: NSPoint(x: 5.0, y: 14.8))
            head.line(to: NSPoint(x: 7.8, y: 11.5))
            head.curve(to: NSPoint(x: 10.2, y: 11.5), controlPoint1: NSPoint(x: 8.5, y: 11.9), controlPoint2: NSPoint(x: 9.5, y: 11.9))
            head.line(to: NSPoint(x: 13.0, y: 14.8))
            head.line(to: NSPoint(x: 15.8, y: 8.2))
            head.line(to: NSPoint(x: 15.8, y: 2.6))
            head.curve(to: NSPoint(x: 2.2, y: 2.6), controlPoint1: NSPoint(x: 14.8, y: 0.8), controlPoint2: NSPoint(x: 3.2, y: 0.8))
            head.close()

            if isAwake {
                head.fill()
                context.saveGraphicsState()
                context.compositingOperation = .clear

                NSBezierPath(ovalIn: NSRect(x: 5.5, y: 6.1, width: 2.3, height: 2.8)).fill()
                NSBezierPath(ovalIn: NSRect(x: 10.2, y: 6.1, width: 2.3, height: 2.8)).fill()

                let nose = NSBezierPath()
                nose.move(to: NSPoint(x: 8.4, y: 5.1))
                nose.line(to: NSPoint(x: 9.0, y: 4.6))
                nose.line(to: NSPoint(x: 9.6, y: 5.1))
                nose.close()
                nose.fill()
                context.restoreGraphicsState()
                NSBezierPath(ovalIn: NSRect(x: 6.3, y: 6.8, width: 0.7, height: 1.5)).fill()
                NSBezierPath(ovalIn: NSRect(x: 11.0, y: 6.8, width: 0.7, height: 1.5)).fill()
            } else {
                head.stroke()

                let leftEar = NSBezierPath()
                leftEar.lineWidth = 1
                leftEar.move(to: NSPoint(x: 4.1, y: 9.0))
                leftEar.line(to: NSPoint(x: 5.0, y: 12.6))
                leftEar.stroke()

                let rightEar = NSBezierPath()
                rightEar.lineWidth = 1
                rightEar.move(to: NSPoint(x: 13.9, y: 9.0))
                rightEar.line(to: NSPoint(x: 13.0, y: 12.6))
                rightEar.stroke()

                let leftEye = NSBezierPath()
                leftEye.lineWidth = 1.35
                leftEye.lineCapStyle = .round
                leftEye.move(to: NSPoint(x: 5.5, y: 7.7))
                leftEye.curve(to: NSPoint(x: 7.8, y: 7.7), controlPoint1: NSPoint(x: 6.0, y: 6.8), controlPoint2: NSPoint(x: 7.3, y: 6.8))
                leftEye.stroke()

                let rightEye = NSBezierPath()
                rightEye.lineWidth = 1.35
                rightEye.lineCapStyle = .round
                rightEye.move(to: NSPoint(x: 10.2, y: 7.7))
                rightEye.curve(to: NSPoint(x: 12.5, y: 7.7), controlPoint1: NSPoint(x: 10.7, y: 6.8), controlPoint2: NSPoint(x: 12.0, y: 6.8))
                rightEye.stroke()

                let nose = NSBezierPath()
                nose.move(to: NSPoint(x: 8.5, y: 5.3))
                nose.line(to: NSPoint(x: 9.0, y: 4.9))
                nose.line(to: NSPoint(x: 9.5, y: 5.3))
                nose.close()
                nose.fill()

                let mouth = NSBezierPath()
                mouth.lineWidth = 0.8
                mouth.move(to: NSPoint(x: 9.0, y: 4.9))
                mouth.line(to: NSPoint(x: 9.0, y: 4.4))
                mouth.curve(to: NSPoint(x: 8.3, y: 4.3), controlPoint1: NSPoint(x: 8.8, y: 4.0), controlPoint2: NSPoint(x: 8.5, y: 4.0))
                mouth.move(to: NSPoint(x: 9.0, y: 4.4))
                mouth.curve(to: NSPoint(x: 9.7, y: 4.3), controlPoint1: NSPoint(x: 9.5, y: 4.0), controlPoint2: NSPoint(x: 9.2, y: 4.0))
                mouth.stroke()

                let z = NSBezierPath()
                z.lineWidth = 0.9
                z.lineCapStyle = .round
                z.move(to: NSPoint(x: 15.0, y: 16.8))
                z.line(to: NSPoint(x: 16.5, y: 16.8))
                z.line(to: NSPoint(x: 15.0, y: 15.4))
                z.line(to: NSPoint(x: 16.5, y: 15.4))
                z.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
