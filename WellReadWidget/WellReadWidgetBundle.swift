//
//  WellReadWidgetBundle.swift
//  WellReadWidget
//

import WidgetKit
import SwiftUI

@main
struct WellReadWidgetBundle: WidgetBundle {
    var body: some Widget {
        WellReadWidget()
    }
}

struct WellReadWidget: Widget {
    let kind: String = "WellReadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpineTimelineProvider()) { entry in
            SpineWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SPINE")
        .description("Your reading stack and what people you follow are reading now.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
