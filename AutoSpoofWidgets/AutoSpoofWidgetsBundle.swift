//
//  AutoSpoofWidgetsBundle.swift
//  AutoSpoofWidgets
//
//  Live Activity & Dynamic Island kieu Grab cho AutoSpoof VN.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AutoSpoofWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AutoSpoofLiveActivity()
    }
}

struct AutoSpoofLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpoofActivityAttributes.self) { context in
            // MARK: - Man hinh Khoa (Lock Screen Banner kieu Grab)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.flightNumber != nil ? "airplane.departure" : "location.north.circle.fill")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(context.state.flightNumber != nil ? "AutoSpoof Bay Quốc Tế" : "AutoSpoof GPS Đang Chạy")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(context.state.isHalted ? Color.red : Color.green)
                            .frame(width: 8, height: 8)
                        Text(context.state.isHalted ? "TẠM DỪNG" : "HOẠT ĐỘNG")
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(context.state.isHalted ? .red : .green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.stateName)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.primary)
                        Text(context.state.statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(context.state.speedKmh))")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundColor(.green)
                        Text("km/h")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }

                if let progress = context.state.flightProgress, let flightNo = context.state.flightNumber {
                    VStack(spacing: 4) {
                        ProgressView(value: progress, total: 1.0)
                            .tint(.green)
                        HStack {
                            Text(flightNo)
                                .font(.caption2.weight(.bold))
                            Spacer()
                            Text("\(Int(progress * 100))% hành trình")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(context.state.coordinateText)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(context.state.activeSource)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(14)
            .background(ContainerRelativeShape().fill(.ultraThinMaterial))
        } dynamicIsland: { context in
            // MARK: - Dynamic Island (Mo rong & Thu gon kieu Grab)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.flightNumber != nil ? "airplane" : "location.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.stateName)
                                .font(.headline.weight(.bold))
                            Text(context.state.activeSource)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(context.state.speedKmh))")
                                .font(.title2.weight(.heavy))
                                .foregroundColor(.green)
                            Text("km/h")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(context.state.isHalted ? "Đã dừng" : "GPS Live")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(context.state.isHalted ? .red : .green)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if let progress = context.state.flightProgress {
                            ProgressView(value: progress, total: 1.0)
                                .tint(.green)
                        } else {
                            Text("Toạ độ: \(context.state.coordinateText)")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: context.state.flightNumber != nil ? "airplane" : "location.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text(context.state.stateName)
                        .font(.caption2.weight(.bold))
                }
            } compactTrailing: {
                Text("\(Int(context.state.speedKmh))k")
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(.green)
            } minimal: {
                Image(systemName: context.state.flightNumber != nil ? "airplane" : "location.fill")
                    .foregroundColor(.green)
                    .font(.caption2)
            }
        }
    }
}
