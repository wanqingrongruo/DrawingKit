//
//  DrawingToolState.swift
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

import CoreFoundation
import UIKit

public protocol StateIdentifier {
    var id: String { get set }
}

public enum DrawingToolState: Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case brushState
        case eraserState
    }

    public enum Key: Int32, RawRepresentable, CaseIterable, Codable {
        case pen = 0
        case arrow = 1
        case marker = 2
        case chartlet = 3
        case rainbow = 4
        case neon = 5
        case blur = 6
        case eraser = 7
        case dash
    }

    public struct BrushState: Equatable, Codable, StateIdentifier {
        private enum CodingKeys: String, CodingKey {
            case color
            case size
            case images
            case dashSize
            case renderStyle
            case offset
        }

        public var id: String = UUID().uuidString
        public let color: DrawingColor
        public let size: CGFloat
        public let images: [UIImage?]
        public var dashSize: CGFloat? = nil // 对 marker笔, 取值范围 0 - 1, 有值, 则 .marker 的 笔会画成虚线. 对 dash 笔, 0 - 无穷
        public var renderStyle: Int = 0 // 对 .chartlet 样式的笔起作用, 决定每一笔使用的贴图从 images 中获取的方式, 0: 表示顺序, 1: 表示随机
        public var offset: CGFloat = 0 // 偏移量, 对 .chartlet 样式的笔起作用, 决定间距. (-1, 1), 默认值: 0

        public init(color: DrawingColor, size: CGFloat, images: [UIImage?] = [], dashSize: CGFloat? = nil, renderStyle: Int = 0, offset: CGFloat = 0) {
            self.color = color
            self.size = size
            self.images = images
            self.dashSize = dashSize
            self.renderStyle = renderStyle
            self.offset = offset
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.color = try container.decode(DrawingColor.self, forKey: .color)
            self.size = try container.decode(CGFloat.self, forKey: .size)
            if let data = try container.decodeIfPresent([Data].self, forKey: .images) {
                images = data.map({ UIImage(data: $0) })
            } else {
                images = []
            }

            dashSize = try container.decodeIfPresent(CGFloat.self, forKey: .dashSize)
            renderStyle = try container.decode(Int.self, forKey: .renderStyle)
            offset = try container.decode(CGFloat.self, forKey: .offset)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.color, forKey: .color)
            try container.encode(self.size, forKey: .size)
            let datas = self.images.map({ $0?.pngData() }).compactMap({ $0 })
            if !datas.isEmpty {
                try container.encode(datas, forKey: .images)
            }

            try container.encodeIfPresent(self.dashSize, forKey: .dashSize)
            try container.encode(renderStyle, forKey: .renderStyle)
            try container.encode(offset, forKey: .offset)
        }

        public func withUpdatedColor(_ color: DrawingColor) -> BrushState {
            return BrushState(color: color, size: self.size, images: self.images, dashSize: self.dashSize, renderStyle: self.renderStyle, offset: self.offset)
        }

        public func withUpdatedSize(_ size: CGFloat) -> BrushState {
            return BrushState(color: self.color, size: size, images: self.images, dashSize: self.dashSize, renderStyle: self.renderStyle, offset: self.offset)
        }

        public func withUpdatedImage(_ images: [UIImage?]) -> BrushState {
            return BrushState(color: self.color, size: size, images: images, dashSize: self.dashSize, renderStyle: self.renderStyle, offset: self.offset)
        }

        public func withUpdatedDashSize(_ dashSize: CGFloat?) -> BrushState {
            return BrushState(color: self.color, size: self.size, images: self.images, dashSize: dashSize, renderStyle: self.renderStyle, offset: self.offset)
        }

        public func withUpdatedRenderStyle(_ renderStyle: Int) -> BrushState {
            return BrushState(color: self.color, size: self.size, images: self.images, dashSize: dashSize, renderStyle: renderStyle, offset: self.offset)
        }

        public func withUpdatedOffset(_ offset: CGFloat) -> BrushState {
            return BrushState(color: self.color, size: self.size, images: self.images, dashSize: dashSize, renderStyle: self.renderStyle, offset: offset)
        }
    }

    public struct EraserState: Equatable, Codable, StateIdentifier {
        private enum CodingKeys: String, CodingKey {
            case size
        }

        public var id: String = UUID().uuidString

        public let size: CGFloat

        public init(size: CGFloat) {
            self.size = size
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.size = try container.decode(CGFloat.self, forKey: .size)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.size, forKey: .size)
        }

        public func withUpdatedSize(_ size: CGFloat) -> EraserState {
            return EraserState(size: size)
        }
    }

    case pen(BrushState)
    case arrow(BrushState)
    case marker(BrushState)
    case chartlet(BrushState)
    case rainbow(BrushState)
    case neon(BrushState)
    case blur(EraserState) // 不支持视频
    case eraser(EraserState)
    case dash(BrushState)

    public var canChangeColor: Bool {
        switch self {
        case .pen, .arrow, .marker, .neon, .dash:
            return true
        default:
            return false
        }
    }

    public func withUpdatedColor(_ color: DrawingColor) -> DrawingToolState {
        switch self {
        case let .pen(state):
            return .pen(state.withUpdatedColor(color))
        case let .arrow(state):
            return .arrow(state.withUpdatedColor(color))
        case let .marker(state):
            return .marker(state.withUpdatedColor(color))
        case let .chartlet(state):
            return .chartlet(state.withUpdatedColor(color))
        case let .rainbow(state):
            return .rainbow(state.withUpdatedColor(color))
        case let .neon(state):
            return .neon(state.withUpdatedColor(color))
        case let .dash(state):
            return .dash(state.withUpdatedColor(color))
        case .blur, .eraser:
            return self
        }
    }

    public func withUpdatedSize(_ size: CGFloat) -> DrawingToolState {
        switch self {
        case let .pen(state):
            return .pen(state.withUpdatedSize(size))
        case let .arrow(state):
            return .arrow(state.withUpdatedSize(size))
        case let .marker(state):
            return .marker(state.withUpdatedSize(size))
        case let .chartlet(state):
            return .chartlet(state.withUpdatedSize(size))
        case let .rainbow(state):
            return .rainbow(state.withUpdatedSize(size))
        case let .neon(state):
            return .neon(state.withUpdatedSize(size))
        case let .blur(state):
            return .blur(state.withUpdatedSize(size))
        case let .eraser(state):
            return .eraser(state.withUpdatedSize(size))
        case let .dash(state):
            return .dash(state.withUpdatedSize(size))
        }
    }

    public func withUpdatedImage(_ images: [UIImage?]) -> DrawingToolState {
        switch self {
        case let .marker(state):
            return .marker(state.withUpdatedImage(images))
        case let .chartlet(state):
            return .chartlet(state.withUpdatedImage(images))
        case let .rainbow(state):
            return .rainbow(state.withUpdatedImage(images))
        default:
            return self
        }
    }

    public func withUpdatedDashSize(_ size: CGFloat?) -> DrawingToolState {
        switch self {
        case let .marker(state):
            return .marker(state.withUpdatedDashSize(size))
        case let .dash(state):
            return .dash(state.withUpdatedDashSize(size))
        default:
            return self
        }
    }

    public func withUpdatedRenderStyle(_ renderStyle: Int) -> DrawingToolState {
        switch self {
        case let .chartlet(state):
            return .chartlet(state.withUpdatedRenderStyle(renderStyle))
        default:
            return self
        }
    }

    public func withUpdatedOffset(_ offset: CGFloat) -> DrawingToolState {
        switch self {
        case let .chartlet(state):
            return .chartlet(state.withUpdatedOffset(offset))
        default:
            return self
        }
    }


    public var state: StateIdentifier {
        switch self {
        case let .pen(state),
            let .arrow(state),
            let .marker(state),
            let .chartlet(state),
            let .neon(state),
            let .rainbow(state),
            let .dash(state):
            return state
        case let .blur(state), let .eraser(state):
            return state
        }
    }

    public var color: DrawingColor? {
        switch self {
        case let .pen(state), let .arrow(state), let .marker(state), let .neon(state), let .dash(state):
            return state.color
        default:
            return nil
        }
    }

    public var size: CGFloat? {
        switch self {
        case let .pen(state), let .arrow(state), let .marker(state), let .chartlet(state), let .neon(state), let .rainbow(state), let .dash(state):
            return state.size
        case let .blur(state), let .eraser(state):
            return state.size
        }
    }

    public var images: [UIImage?] {
        switch self {
        case let .marker(state), let .chartlet(state), let .rainbow(state):
            return state.images
        default:
            return []
        }
    }

    public var dashSize: CGFloat? {
        switch self {
        case let .marker(state):
            return state.dashSize
        default:
            return nil
        }
    }

    public var key: DrawingToolState.Key {
        switch self {
        case .pen:
            return .pen
        case .arrow:
            return .arrow
        case .marker:
            return .marker
        case .chartlet:
            return .chartlet
        case .rainbow:
            return .rainbow
        case .neon:
            return .neon
        case .blur:
            return .blur
        case .eraser:
            return .eraser
        case .dash:
            return .dash
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeValue = try container.decode(Int32.self, forKey: .type)
        if let type = DrawingToolState.Key(rawValue: typeValue) {
            switch type {
            case .pen:
                self = .pen(try container.decode(BrushState.self, forKey: .brushState))
            case .arrow:
                self = .arrow(try container.decode(BrushState.self, forKey: .brushState))
            case .marker:
                self = .marker(try container.decode(BrushState.self, forKey: .brushState))
            case .chartlet:
                self = .chartlet(try container.decode(BrushState.self, forKey: .brushState))
            case .rainbow:
                self = .rainbow(try container.decode(BrushState.self, forKey: .brushState))
            case .neon:
                self = .neon(try container.decode(BrushState.self, forKey: .brushState))
            case .blur:
                self = .blur(try container.decode(EraserState.self, forKey: .eraserState))
            case .eraser:
                self = .eraser(try container.decode(EraserState.self, forKey: .eraserState))
            case .dash:
                self = .dash(try container.decode(BrushState.self, forKey: .brushState))
            }
        } else {
            self = .pen(BrushState(color: DrawingColor(rgb: 0x000000), size: 0.5))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pen(state):
            try container.encode(DrawingToolState.Key.pen.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .arrow(state):
            try container.encode(DrawingToolState.Key.arrow.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .marker(state):
            try container.encode(DrawingToolState.Key.marker.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .chartlet(state):
            try container.encode(DrawingToolState.Key.chartlet.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .rainbow(state):
            try container.encode(DrawingToolState.Key.rainbow.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .neon(state):
            try container.encode(DrawingToolState.Key.neon.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .blur(state):
            try container.encode(DrawingToolState.Key.blur.rawValue, forKey: .type)
            try container.encode(state, forKey: .eraserState)
        case let .eraser(state):
            try container.encode(DrawingToolState.Key.eraser.rawValue, forKey: .type)
            try container.encode(state, forKey: .eraserState)
        case let .dash(state):
            try container.encode(DrawingToolState.Key.dash.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        }
    }

    public static func == (lhs: DrawingToolState, rhs: DrawingToolState) -> Bool {
        if lhs.key == rhs.key {
            if (lhs.state.id == rhs.state.id) {
                return true
            }
        }

        return false
    }
}

public struct DrawingState: Equatable {
    public let selectedIndex: Int
    public let tools: [DrawingToolState]

    public var currentToolState: DrawingToolState? {
        if selectedIndex < tools.count {
            return tools[selectedIndex]
        }

        return nil
    }

    public func appendTool(_ tool: DrawingToolState) -> DrawingState {
        var array =  tools
        array.append(tool)
        return DrawingState(selectedIndex: selectedIndex, tools: array)
    }

    public func toolState(for index: Int) -> DrawingToolState? {
        if index < tools.count {
            return tools[index]
        }

        return nil
    }

    public func withUpdatedSelectedIndex(_ index: Int) -> DrawingState {
        return DrawingState(
            selectedIndex: index,
            tools: self.tools
        )
    }

    public func withUpdatedTools(_ tools: [DrawingToolState], _ selectedIndex: Int) -> DrawingState {
        return DrawingState(
            selectedIndex: selectedIndex,
            tools: tools
        )
    }

    public func withUpdatedColor(_ color: DrawingColor) -> DrawingState {
        var tools = self.tools
        if selectedIndex < tools.count {
            let updated = tools[selectedIndex].withUpdatedColor(color)
            tools.remove(at: selectedIndex)
            tools.insert(updated, at: selectedIndex)
        }

        return DrawingState(
            selectedIndex: self.selectedIndex,
            tools: tools
        )
    }

    public func withUpdatedSize(_ size: CGFloat) -> DrawingState {
        var tools = self.tools
        if selectedIndex < tools.count {
            let updated = tools[selectedIndex].withUpdatedSize(size)
            tools.remove(at: selectedIndex)
            tools.insert(updated, at: selectedIndex)
        }

        return DrawingState(
            selectedIndex: self.selectedIndex,
            tools: tools
        )
    }

    public static var initial: DrawingState {
        return DrawingState(
            selectedIndex: 0,
            tools: [
                .pen(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff453a), size: 0.23)),
                .arrow(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff8a00), size: 0.23)),
                .marker(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2)),
                .chartlet(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.3)),
                .neon(DrawingToolState.BrushState(color: DrawingColor(rgb: 0x34c759), size: 0.4)),
                .rainbow(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2)),
                .blur(DrawingToolState.EraserState(size: 0.5)),
                .eraser(DrawingToolState.EraserState(size: 0.5))
            ]
        )
    }

    public func forVideo() -> DrawingState {
        return DrawingState(
            selectedIndex: 0,
            tools: self.tools.filter { tool in
                if case .blur = tool {
                    return false
                } else {
                    return true
                }
            }
        )
    }
}

public final class DrawingSettings: Codable, Equatable {
    public let tools: [DrawingToolState]

    public init(tools: [DrawingToolState]) {
        self.tools = tools
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        if let data = try container.decodeIfPresent(Data.self, forKey: "tools"), let tools = try? JSONDecoder().decode([DrawingToolState].self, from: data) {
            self.tools = tools
        } else {
            self.tools = DrawingState.initial.tools
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        if let data = try? JSONEncoder().encode(self.tools) {
            try container.encode(data, forKey: "tools")
        }
    }

    public static func ==(lhs: DrawingSettings, rhs: DrawingSettings) -> Bool {
        return lhs.tools == rhs.tools
    }
}

public struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
    public var stringValue: String

    public init?(stringValue: String) {
        self.stringValue = stringValue
    }

    public init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    public init(stringLiteral: String) {
        self.stringValue = stringLiteral
    }

    public var intValue: Int? {
        return nil
    }

    public init?(intValue: Int) {
        return nil
    }
}
