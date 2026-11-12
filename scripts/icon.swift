import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.clear.setFill(); NSRect(x:0,y:0,width:1024,height:1024).fill()
let rect = NSRect(x:64,y:64,width:896,height:896)
let shape = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
NSGradient(starting: NSColor(calibratedRed:0.10,green:0.16,blue:0.24,alpha:1), ending: NSColor(calibratedRed:0.025,green:0.045,blue:0.08,alpha:1))!.draw(in:shape,angle: -90)
let heights: [CGFloat] = [80,140,240,380,540,340,180,280,460,300,160,100]
for (i,h) in heights.enumerated() {
 let bar = NSBezierPath(roundedRect:NSRect(x:220+CGFloat(i)*49,y:512-h/2,width:27,height:h),xRadius:13.5,yRadius:13.5)
 NSColor(calibratedRed:0.15,green:0.85,blue:0.93,alpha:1).setFill(); bar.fill()
}
let line = NSBezierPath(roundedRect:NSRect(x:503,y:200,width:5,height:624),xRadius:2,yRadius:2)
NSColor.white.withAlphaComponent(0.9).setFill(); line.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
