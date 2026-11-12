import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class Player: ObservableObject {
    @Published var audio: AVAudioPlayer?
    @Published var rate: Float = 1 { didSet { audio?.rate = rate } }
    @Published var peaks: [Float] = []
    @Published var time = 0.0
    @Published var name = "음원을 열어주세요"
    @Published var error: String?
    @Published var loading = false
    var analysis: Task<[Float], Error>?
    var generation = UUID()
    var timer: Timer?
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.time = self?.audio?.currentTime ?? 0 }
        }
    }
    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func load(_ url: URL) {
        analysis?.cancel(); audio?.stop(); audio = nil; peaks = []; time = 0
        let id = UUID(); generation = id
        do {
            audio = try AVAudioPlayer(contentsOf: url)
            audio?.enableRate = true; rate = 1; audio?.rate = rate; audio?.prepareToPlay(); name = url.lastPathComponent; loading = true
            Task {
                do {
                    let work = Task.detached(priority: .userInitiated) {
                        let file = try AVAudioFile(forReading: url)
                        let count = max(1, Int(ceil(Double(file.length) / file.processingFormat.sampleRate / 0.01)))
                        var values = [Float](repeating: 0, count: count)
                        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return values }
                        var offset: Int64 = 0
                        while offset < file.length {
                            try Task.checkCancellation()
                            try file.read(into: buffer)
                            let frames = Int(buffer.frameLength)
                            if frames == 0 { break }
                            if let data = buffer.floatChannelData {
                                for i in 0..<frames {
                                    let bin = min(count - 1, Int((offset + Int64(i)) * Int64(count) / max(1, file.length)))
                                    for channel in 0..<Int(buffer.format.channelCount) { values[bin] = max(values[bin], abs(data[channel][i])) }
                                }
                            }
                            offset += Int64(frames)
                        }
                        return values
                    }
                    analysis = work
                    let result = try await work.value
                    guard generation == id else { return }
                    peaks = result; loading = false
                } catch { if generation == id { loading = false; self.error = error.localizedDescription } }
            }
        } catch { loading = false; self.error = error.localizedDescription }
    }
    func toggle() {
        guard let audio else { return }
        if audio.isPlaying { audio.pause() } else { if audio.currentTime >= audio.duration - 0.05 { audio.currentTime = 0 }; audio.play() }
        objectWillChange.send()
    }
    func seek(_ fraction: Double) { audio?.currentTime = max(0, min(1, fraction)) * (audio?.duration ?? 0); time = audio?.currentTime ?? 0 }
}
func timestamp(_ value: Double) -> String { String(format: "%02d:%02d", Int(max(0,value))/60, Int(max(0,value))%60) }
// Native mouse handling keeps secondary dragging independent from seeking.
struct WaveformMouseInput: NSViewRepresentable {
    var seek: (Double, Bool) -> Void
    var pan: (Double) -> Void
    var hover: (Double?) -> Void
    func makeNSView(context: Context) -> MouseView { MouseView() }
    func updateNSView(_ view: MouseView, context: Context) {
        view.seek = seek; view.pan = pan; view.hover = hover
    }
    final class MouseView: NSView {
        var seek: ((Double, Bool) -> Void)?
        var pan: ((Double) -> Void)?
        var hover: ((Double?) -> Void)?
        var lastX: CGFloat = 0
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
        }
        func fraction(_ event: NSEvent) -> Double {
            max(0, min(1, convert(event.locationInWindow, from: nil).x / max(1, bounds.width)))
        }
        override func mouseDown(with event: NSEvent) { seek?(fraction(event), false) }
        override func mouseDragged(with event: NSEvent) { seek?(fraction(event), false) }
        override func mouseUp(with event: NSEvent) { seek?(fraction(event), true) }
        override func rightMouseDown(with event: NSEvent) {
            lastX = convert(event.locationInWindow, from: nil).x
        }
        override func rightMouseDragged(with event: NSEvent) {
            let x = convert(event.locationInWindow, from: nil).x
            pan?((lastX - x) / max(1, bounds.width)); lastX = x
            hover?(nil)
        }
        override func rightMouseUp(with event: NSEvent) {}
        override func mouseMoved(with event: NSEvent) { hover?(fraction(event)) }
        override func mouseExited(with event: NSEvent) { hover?(nil) }
    }
}
struct ContentView: View {
    @StateObject var player = Player()
    @State var drag: Double?
    @State var hover: Double?
    @State var span = 1.0
    @State var start = 0.0
    @State var follow = true
    func zoom(_ factor: Double) {
        let duration = player.audio?.duration ?? 0
        guard duration > 0 else { return }
        let position = player.time / duration
        let center = position >= start && position <= start + span ? position : start + span / 2
        span = min(1, max(min(1, 5 / duration), span * factor))
        start = max(0, min(1 - span, center - span / 2))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack { VStack(alignment: .leading) { Text("WAVE PLAYER  ·  v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"))").font(.caption).tracking(3).foregroundStyle(.secondary); Text(player.name).font(.title2.bold()).lineLimit(1) }; Spacer(); Button("음원 열기", systemImage: "folder") { player.open() }.keyboardShortcut("o") }
            HStack {
                Button("−") { zoom(2) }; Button("＋") { zoom(0.5) }
                Button("전체 보기") { span = 1; start = 0 }
                Text("\(Int((1/span).rounded()))× 확대").foregroundStyle(.secondary)
                Spacer()
                Toggle("따라가기", isOn: $follow).toggleStyle(.switch)
            }
            GeometryReader { geo in
                let duration = player.audio?.duration ?? 0
                let absolute = drag ?? (duration > 0 ? player.time / duration : 0)
                let fraction = (absolute - start) / span
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.04))
                    Canvas { context, size in
                        let values = player.peaks
                        let columns = max(1, Int(size.width))
                        for column in 0..<columns {
                            let low = max(0, min(values.count, Int((start + Double(column)/Double(columns)*span)*Double(values.count))))
                            let endFraction: Double = start + Double(column + 1) / Double(columns) * span
                            let endIndex = Int(endFraction * Double(values.count)) + 1
                            let high = max(low, min(values.count, endIndex))
                            let peak = low < high ? values[low..<high].max() ?? 0 : 0
                            let height = max(2, CGFloat(peak) * size.height * 0.85)
                            context.fill(Path(CGRect(x: CGFloat(column), y: (size.height-height)/2, width: 1, height: height)), with: .color(Double(column)/Double(columns) <= fraction ? .cyan : .gray.opacity(0.6)))
                        }
                        context.fill(Path(CGRect(x: fraction * size.width, y: 0, width: 2, height: size.height)), with: .color(.white))
                    }.padding(.vertical, 20)
                    if player.loading { ProgressView("파형 분석 중…") }
                    if player.audio == nil { Text("음원 파일을 여기에 놓으세요").foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
                .overlay {
                    WaveformMouseInput(seek: { fraction, ended in
                        let target = start + fraction * span
                        player.seek(target)
                        drag = ended ? nil : target
                    }, pan: { delta in
                        guard span < 1 else { return }
                        follow = false
                        start = max(0, min(1 - span, start + delta * span))
                    }, hover: { hover = $0 })
                    .help("좌클릭: 재생 위치 이동 · 우클릭 드래그: 파형 화면 이동")
                }
                .overlay(alignment: .topLeading) { if let hover { Text(timestamp((start + hover * span) * duration)).font(.caption.monospacedDigit()).padding(6).background(.black.opacity(0.8)).allowsHitTesting(false).offset(x: min(geo.size.width-55,hover*geo.size.width)) } }
            }.frame(minHeight: 200)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        let values = player.peaks
                        for x in 0..<max(1,Int(size.width)) {
                            let low = min(values.count, Int(Double(x)/size.width*Double(values.count)))
                            let high = min(values.count, Int(Double(x+1)/size.width*Double(values.count))+1)
                            let peak = low < high ? values[low..<high].max() ?? 0 : 0
                            let h = max(1,CGFloat(peak)*size.height)
                            context.fill(Path(CGRect(x: CGFloat(x), y: (size.height-h)/2,width: 1,height: h)),with: .color(.gray))
                        }
                    }
                    Rectangle().fill(.cyan.opacity(0.15)).overlay(Rectangle().stroke(.cyan)).frame(width: geo.size.width*span).offset(x: geo.size.width*start)
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in follow = false; start = max(0,min(1-span,value.location.x/geo.size.width-span/2)) })
            }.frame(height: 40)
            HStack { Text("00:00"); Spacer(); Text(timestamp(player.audio?.duration ?? 0)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Button { player.toggle() } label: { Image(systemName: player.audio?.isPlaying == true ? "pause.fill" : "play.fill").font(.title).frame(width: 48,height: 40) }.keyboardShortcut(.space, modifiers: []).disabled(player.audio == nil)
                Text("\(timestamp(drag.map { $0 * (player.audio?.duration ?? 0) } ?? player.time)) / \(timestamp(player.audio?.duration ?? 0))").monospacedDigit()
                Picker("배속", selection: $player.rate) {
                    ForEach([Float(0.25),0.5,0.75,1], id: \.self) { rate in Text(String(format: "%g×",rate)).tag(rate) }
                }.frame(width: 130)
                Spacer(); Image(systemName: "speaker.wave.2")
                Slider(value: Binding(get: { Double(player.audio?.volume ?? 1) }, set: { player.audio?.volume = Float($0); player.objectWillChange.send() }), in: 0...1).frame(width: 130)
            }
        }.padding(32).frame(minWidth: 720,minHeight: 440).preferredColorScheme(.dark)
        .onChange(of: player.name) { _, _ in span = 1; start = 0; follow = true }
        .onChange(of: follow) { _, enabled in
            if enabled, let duration = player.audio?.duration, duration > 0 {
                start = max(0, min(1 - span, player.time / duration - span / 2))
            }
        }
        .onChange(of: player.time) { _, time in
            guard follow, drag == nil, let duration = player.audio?.duration, duration > 0 else { return }
            let fraction = time/duration
            if fraction < start || fraction > start + span { start = max(0,min(1-span,fraction)) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in player.load(url) } } }; return true
        }
        .alert("음원을 불러올 수 없습니다", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) { Button("확인") { player.error = nil } } message: { Text(player.error ?? "") }
    }
}
@main struct WavePlayerApp: App { var body: some Scene { WindowGroup { ContentView() } } }
