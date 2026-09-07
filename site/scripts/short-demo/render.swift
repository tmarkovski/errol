import AppKit
import CoreGraphics
import Foundation

// A deterministic, standalone short film. Layout uses top-left coordinates.
// The dot, tapered wake, bloom, and receiving outline follow Errol's native
// TransferDrawing treatment; the narrative clock is slowed for legibility.
let width = 1280, height = 800, fps = 30
let duration = 10.5
let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ERROL_DEMO_OUTPUT"] ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().path)
let white = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1)
let secondary = NSColor(srgbRed: 0.59, green: 0.60, blue: 0.61, alpha: 1)
let gold = NSColor(srgbRed: 1, green: 0.77, blue: 0.20, alpha: 1)
let dotGold = NSColor(srgbRed: 1, green: 0.90, blue: 0.52, alpha: 1)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(height) - y - h, width: w, height: h)
}
func native(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: CGFloat(height) - p.y) }
func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
func smooth(_ x: Double) -> Double { let p = clamp(x); return p*p*(3-2*p) }
func opacity(_ t: Double, after start: Double, duration: Double = 0.25) -> CGFloat {
    CGFloat(smooth((t-start)/duration))
}
func withAlpha(_ alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current!.cgContext.setAlpha(alpha)
    body()
    NSGraphicsContext.restoreGraphicsState()
}
func round(_ box: CGRect, _ fill: NSColor, radius: CGFloat = 17, stroke: NSColor? = nil, line: CGFloat = 1) {
    let p = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    fill.setFill(); p.fill()
    if let stroke { stroke.setStroke(); p.lineWidth = line; p.stroke() }
}
func text(_ string: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 40,
          size: CGFloat = 24, weight: NSFont.Weight = .regular, color: NSColor = white,
          alignment: NSTextAlignment = .left, lineHeight: CGFloat? = nil) {
    let para = NSMutableParagraphStyle()
    para.alignment = alignment
    para.lineBreakMode = .byWordWrapping
    if let lineHeight { para.minimumLineHeight = lineHeight; para.maximumLineHeight = lineHeight }
    (string as NSString).draw(in: rect(x,y,w,h), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: para,
    ])
}
func line(_ a: CGPoint, _ b: CGPoint, color: NSColor, width: CGFloat = 1) {
    let p = NSBezierPath(); p.move(to: native(a)); p.line(to: native(b)); p.lineWidth = width
    p.lineCapStyle = .round; color.setStroke(); p.stroke()
}
func circle(_ p: CGPoint, radius: CGFloat, fill: NSColor) {
    fill.setFill(); NSBezierPath(ovalIn: rect(p.x-radius,p.y-radius,radius*2,radius*2)).fill()
}
func upArrow(x: CGFloat, y: CGFloat, enabled: Bool) {
    circle(CGPoint(x:x,y:y), radius: 15, fill: color(0.78,0.79,0.80, enabled ? 1 : 0.12))
    let ink = enabled ? color(0.14,0.15,0.16) : color(0.48,0.49,0.51)
    line(CGPoint(x:x,y:y+6), CGPoint(x:x,y:y-6), color: ink, width: 2.2)
    line(CGPoint(x:x,y:y-6), CGPoint(x:x-4.5,y:y-1.5), color: ink, width: 2.2)
    line(CGPoint(x:x,y:y-6), CGPoint(x:x+4.5,y:y-1.5), color: ink, width: 2.2)
}
let leftPrompt = rect(74,640,512,86)
let rightPrompt = rect(694,640,512,86)
let userSource = CGPoint(x:640,y:150)
let leftCopy = CGPoint(x:523,y:510)
let rightCopy = CGPoint(x:1143,y:510)

func copyButton(x: CGFloat, y: CGFloat, alpha: CGFloat) {
    withAlpha(alpha) {
        let ink = color(0.65,0.66,0.67)
        let rear = NSBezierPath(roundedRect: rect(x,y+1,11,13), xRadius: 2, yRadius: 2)
        rear.lineWidth = 1.4; ink.setStroke(); rear.stroke()
        let front = NSBezierPath(roundedRect: rect(x+4,y+5,11,13), xRadius: 2, yRadius: 2)
        color(0.135,0.14,0.15).setFill(); front.fill(); ink.setStroke(); front.stroke()
        text("Copy",x:x+24,y:y-2,w:58,h:28,size:19,color:ink)
    }
}
func window(x: CGFloat, title: String) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.27)
    shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width:0,height:-10); shadow.set()
    round(rect(x,234,564,522), color(0.135,0.14,0.15), radius: 20)
    NSGraphicsContext.restoreGraphicsState()
    round(rect(x,234,564,522), .clear, radius:20, stroke:color(1,1,1,0.07))
    for (i,c) in [color(1,0.37,0.35),color(1,0.77,0.24),color(0.19,0.80,0.32)].enumerated() {
        circle(CGPoint(x:x+27+CGFloat(i)*21,y:263),radius:6,fill:c)
    }
    text(title,x:x+170,y:249,w:224,h:32,size:21,weight:.semibold,alignment:.center)
}
func composer(_ box: CGRect, placeholder: String, content: String?, alpha: CGFloat = 1) {
    round(box,color(0.184,0.19,0.20),radius:17)
    let x=box.minX, y=CGFloat(height)-box.maxY
    if let content {
        withAlpha(alpha) { text(content,x:x+21,y:y+18,w:box.width-76,h:62,size:21,lineHeight:27) }
    } else {
        text(placeholder,x:x+21,y:y+29,w:box.width-76,h:34,size:21,color:secondary.withAlphaComponent(0.74))
    }
    upArrow(x:box.maxX-31,y:y+43,enabled:content != nil)
}
func bubble(_ string: String, x: CGFloat, y: CGFloat, w: CGFloat, alpha: CGFloat) {
    withAlpha(alpha) {
        round(rect(x,y,w,58),color(0.205,0.21,0.22),radius:16)
        text(string,x:x+19,y:y+15,w:w-38,h:34,size:22)
    }
}
func assistant(_ string: String, x: CGFloat, y: CGFloat, alpha: CGFloat) {
    withAlpha(alpha) { text(string,x:x,y:y,w:492,h:86,size:27,weight:.medium,lineHeight:35) }
}
func errol(_ t: Double) {
    let switching = opacity(t,after:5.20,duration:0.22)
    NSGraphicsContext.saveGraphicsState()
    let shadow=NSShadow(); shadow.shadowColor=NSColor.black.withAlphaComponent(0.26)
    shadow.shadowBlurRadius=24; shadow.shadowOffset=NSSize(width:0,height:-9); shadow.set()
    round(rect(420,48,440,166),color(0.22,0.225,0.235),radius:20)
    NSGraphicsContext.restoreGraphicsState()
    round(rect(420,48,440,166),.clear,radius:20,stroke:color(1,1,1,0.09))
    text("Errol",x:441,y:66,w:90,h:29,size:19,weight:.semibold)
    withAlpha(1-switching) { text("PROMPT",x:680,y:71,w:155,h:24,size:12,weight:.medium,color:secondary,alignment:.right) }
    withAlpha(switching) { text("STEERING NOTE",x:680,y:71,w:155,h:24,size:12,weight:.medium,color:secondary,alignment:.right) }
    round(rect(438,106,404,88),color(0.145,0.15,0.16),radius:13)
    withAlpha(1-switching) { text("Make onboarding simpler.",x:455,y:133,w:337,h:36,size:23) }
    withAlpha(switching) { text("Keep it to one screen.",x:455,y:133,w:337,h:36,size:23) }
    upArrow(x:815,y:150,enabled:true)
}
struct Flight {
    let startTime: Double
    let travel: Double
    let starts: [CGPoint]
    let destination: CGRect
    var arrival: Double { startTime + travel }
}
let flights = [
    Flight(startTime:0.55,travel:1.05,starts:[userSource],destination:leftPrompt),
    Flight(startTime:3.10,travel:1.00,starts:[leftCopy],destination:rightPrompt),
    Flight(startTime:6.35,travel:1.25,starts:[rightCopy,userSource],destination:leftPrompt),
]
func trajectory(start: CGPoint, end: CGPoint, p: Double, lane: Int) -> CGPoint {
    let e=smooth(p), q=1-e
    let distance=hypot(end.x-start.x,end.y-start.y)
    let bend=min(120,distance*0.18)*(lane==0 ? 1 : 0.55)
    let control=CGPoint(x:(start.x+end.x)/2,y:min(start.y,end.y)-bend)
    return CGPoint(x:q*q*start.x+2*q*e*control.x+e*e*end.x,
                   y:q*q*start.y+2*q*e*control.y+e*e*end.y)
}
func glowingFill(_ path: NSBezierPath, color c: NSColor, opacity: CGFloat, blur: CGFloat, shadowOpacity: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current!.cgContext.setAlpha(opacity)
    let shadow=NSShadow(); shadow.shadowColor=c.withAlphaComponent(shadowOpacity)
    shadow.shadowBlurRadius=blur; shadow.shadowOffset = .zero; shadow.set()
    c.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
}
func drawFlight(_ flight: Flight, time t: Double) {
    guard t>=flight.startTime && t<flight.arrival+1.05 else {return}
    let arrivalAge=max(0,t-flight.arrival)
    let dissolve=clamp(arrivalAge/0.26)
    let movingOpacity=CGFloat(clamp((t-flight.startTime)/0.09)*(1-dissolve))
    let end=CGPoint(x:flight.destination.midX,y:CGFloat(height)-flight.destination.midY)
    for (lane,start) in flight.starts.enumerated() {
        func p(_ time:Double)->CGPoint { trajectory(start:start,end:end,p:(time-flight.startTime)/flight.travel,lane:lane) }
        let head=p(t)
        let points=(0...30).map { p(t-0.24+Double($0)/30*0.24) }
        var left:[CGPoint]=[],right:[CGPoint]=[]
        for i in points.indices {
            let a=points[max(0,i-1)],b=points[min(points.count-1,i+1)]
            let len=max(0.001,hypot(b.x-a.x,b.y-a.y))
            let w=4.1*pow(Double(i)/30,1.5)
            let dx = -(b.y-a.y)/len*w, dy = (b.x-a.x)/len*w
            left.append(CGPoint(x:points[i].x+dx,y:points[i].y+dy))
            right.append(CGPoint(x:points[i].x-dx,y:points[i].y-dy))
        }
        let tail=NSBezierPath(); let shape=left+right.reversed()
        tail.move(to:native(shape[0])); for point in shape.dropFirst(){tail.line(to:native(point))}; tail.close()
        glowingFill(tail,color:gold,opacity:movingOpacity*0.56,blur:9,shadowOpacity:0.6)
        let radius=5.7*(1-dissolve*0.75)
        let dot=NSBezierPath(ovalIn:rect(head.x-radius,head.y-radius,radius*2,radius*2))
        glowingFill(dot,color:dotGold,opacity:movingOpacity,blur:13,shadowOpacity:0.95)
    }
    if t>=flight.arrival {
        let bloomR=6+dissolve*23
        withAlpha(CGFloat((1-dissolve)*0.7)) {
            let bloom=NSBezierPath(ovalIn:rect(end.x-bloomR,end.y-bloomR,bloomR*2,bloomR*2))
            gold.setStroke(); bloom.lineWidth=1.8; bloom.stroke()
        }
        let rise=clamp(arrivalAge/0.09),fall=max(0,1-max(0,arrivalAge-0.22)/0.83)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current!.cgContext.setAlpha(CGFloat(rise*fall*fall))
        let shadow=NSShadow(); shadow.shadowColor=gold.withAlphaComponent(0.8)
        shadow.shadowBlurRadius=11;shadow.shadowOffset = .zero;shadow.set()
        let outline=NSBezierPath(roundedRect:flight.destination,xRadius:17,yRadius:17)
        gold.setStroke();outline.lineWidth=2.3;outline.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
func frame(_ t:Double)->NSBitmapImageRep {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,
                               samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
                               bytesPerRow:width*4,bitsPerPixel:32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)!
    color(0.067,0.075,0.091).setFill();NSBezierPath(rect:rect(0,0,CGFloat(width),CGFloat(height))).fill()
    window(x:48,title:"ChatGPT");window(x:668,title:"Claude")
    errol(t)
    var leftContent:String?=nil,rightContent:String?=nil
    if t>=1.6 && t<2.22 {leftContent="Make onboarding simpler."}
    if t>=4.1 && t<4.75 {rightContent="Start with one useful action."}
    if t>=7.6 && t<8.55 {leftContent="Save the setup for later.\nKeep it to one screen."}
    composer(leftPrompt,placeholder:"Message ChatGPT",content:leftContent)
    composer(rightPrompt,placeholder:"Reply to Claude…",content:rightContent)
    if t>=2.22 {
        bubble("Make onboarding simpler.",x:208,y:327,w:368,alpha:opacity(t,after:2.22))
        let oldAlpha:CGFloat=1-opacity(t,after:8.55)
        assistant("Start with one useful action.",x:82,y:430,alpha:opacity(t,after:2.42)*oldAlpha)
        copyButton(x:484,y:500,alpha:opacity(t,after:2.66)*oldAlpha)
        if t>=8.55 {
            assistant("Put the first useful action\non one screen.",x:82,y:420,alpha:opacity(t,after:8.55,duration:0.35))
            copyButton(x:484,y:518,alpha:opacity(t,after:8.85))
        }
    }
    if t>=4.75 {
        bubble("Start with one useful action.",x:784,y:327,w:412,alpha:opacity(t,after:4.75))
        assistant("Save the setup for later.",x:702,y:430,alpha:opacity(t,after:4.97))
        copyButton(x:1104,y:500,alpha:opacity(t,after:5.18))
    }
    for flight in flights {drawFlight(flight,time:t)}
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
let previewTimes:[(String,Double)]=[
    ("opening",0.0),("opening-flight",1.13),("first-outline",1.76),("single-flight",3.62),
    ("claude-outline",4.25),("steering-ready",6.05),("two-flights",6.97),
    ("meeting",7.56),("steering-outline",7.76),("end",9.5),
]
let stillsOnly=CommandLine.arguments.contains("--stills")
try FileManager.default.createDirectory(at:output.appendingPathComponent("frames"),withIntermediateDirectories:true)
for (name,t) in previewTimes {
    try autoreleasepool {
        try frame(t).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(name).png"))
    }
}
if !stillsOnly {
    for index in 0..<Int(duration*Double(fps)) {
        try autoreleasepool {
            let path=output.appendingPathComponent(String(format:"frames/frame-%04d.png",index))
            try frame(Double(index)/Double(fps)).representation(using:.png,properties:[:])!.write(to:path)
        }
        if index % 60 == 0 {print("Rendered \(index)/\(Int(duration*Double(fps)))")}
    }
}
print("Rendered \(stillsOnly ? "stills" : "film") at \(output.path)")
