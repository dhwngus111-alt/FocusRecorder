import SwiftUI

struct TimerPopoverView: View {
    @ObservedObject var store: FocusStore
    let openHistory: () -> Void
    @State private var minutes = "25"
    @FocusState private var minutesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("집중 타이머").font(.headline)
                Spacer()
                Button("기록 보기") { openHistory() }
                    .buttonStyle(.link)
            }

            Text(TimeText.clock(store.elapsed))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("경과 시간 \(TimeText.duration(store.elapsed))")

            if let session = store.active {
                Text("목표 \(TimeText.duration(session.targetSeconds))")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                HStack {
                    Button(store.isRunning ? "일시정지" : "계속하기") { store.pauseOrResume() }
                        .keyboardShortcut(.space, modifiers: [])
                    Button("집중 종료") { store.stop() }
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    TextField("분", text: $minutes)
                        .focused($minutesFocused)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(start)
                    Text("분")
                    Button("시작") { start() }
                        .disabled(parsedMinutes == nil)
                        .keyboardShortcut(.return, modifiers: [])
                }
                Text("1분부터 1,440분까지 설정할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Toggle("화면에 타이머 띄우기", isOn: $store.overlayVisible)
            Toggle("항상 다른 창 위에 표시", isOn: $store.alwaysOnTop)
            HStack {
                Text("화면 타이머 크기")
                Slider(value: $store.overlayFontSize, in: 12...80, step: 1)
                Text("\(Int(store.overlayFontSize))")
                    .monospacedDigit()
                    .frame(width: 25, alignment: .trailing)
            }
            Text("화면의 숫자를 드래그하여 이동할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 300)
        .onAppear { if store.active == nil { minutesFocused = true } }
    }

    private var parsedMinutes: Int? {
        guard let value = Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1440).contains(value) else { return nil }
        return value
    }

    private func start() {
        guard let value = parsedMinutes else { return }
        store.start(minutes: value)
    }
}

struct HistoryView: View {
    @ObservedObject var store: FocusStore
    @State private var selectedDate = Date()
    @State private var shownMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!

    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
    private var calendar: Calendar { .current }
    private var selectedRecords: [FocusRecord] {
        FocusStatistics.records(on: selectedDate, from: store.records)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("집중 기록").font(.largeTitle.bold())
                HStack(spacing: 12) {
                    statCard("오늘 평균", value: FocusStatistics.average(on: Date(), from: store.records))
                    statCard("이번 주 평균", value: FocusStatistics.weekAverage(containing: Date(), from: store.records))
                }
                Text("평균은 완료·중단한 모든 세션의 실제 집중 시간을 기준으로 계산합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    HStack {
                        Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                        Text(shownMonth.formatted(.dateTime.year().month(.wide)))
                            .font(.title3.bold())
                        Spacer()
                        Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                        ForEach(weekdays, id: \.self) { day in
                            Text(day).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                            if let date {
                                let count = FocusStatistics.records(on: date, from: store.records).count
                                Button {
                                    selectedDate = date
                                } label: {
                                    VStack(spacing: 3) {
                                        Text("\(calendar.component(.day, from: date))")
                                        Circle()
                                            .fill(count > 0 ? Color.accentColor : .clear)
                                            .frame(width: 5, height: 5)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(calendar.isDate(date, inSameDayAs: selectedDate)
                                                ? Color.accentColor.opacity(0.24) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), 기록 \(count)개")
                            } else {
                                Color.clear.frame(height: 42)
                            }
                        }
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.headline)
                    if selectedRecords.isEmpty {
                        Text("이날의 집중 기록이 없습니다.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(selectedRecords) { record in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.headline)
                                    Text("설정 \(TimeText.duration(record.targetSeconds)) · 실제 \(TimeText.duration(record.actualSeconds))")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(record.succeeded ? "성공" : "실패")
                                    .foregroundStyle(record.succeeded ? .green : .orange)
                            }
                            .padding(12)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                Divider()
                Text("표시 설정").font(.headline)
                Toggle("화면에 타이머 띄우기", isOn: $store.overlayVisible)
                Toggle("항상 다른 창 위에 표시", isOn: $store.alwaysOnTop)
                HStack {
                    Text("화면 타이머 숫자 크기")
                    Slider(value: $store.overlayFontSize, in: 12...80, step: 1)
                    Text("\(Int(store.overlayFontSize)) pt").frame(width: 42, alignment: .trailing)
                }
                Text("화면의 숫자를 드래그하여 이동하면 위치가 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 620)
    }

    private func statCard(_ label: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map(TimeText.duration) ?? "기록 없음")
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: shownMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: shownMonth)) else { return [] }
        let offset = (calendar.component(.weekday, from: first) - 1 + 7) % 7
        return Array(repeating: nil, count: offset) + range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: first)
        }.map(Optional.some)
    }

    private func moveMonth(_ amount: Int) {
        if let date = calendar.date(byAdding: .month, value: amount, to: shownMonth) {
            shownMonth = date
        }
    }
}

