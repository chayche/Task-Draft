import UIKit

struct TaskTag {
    let title: String
    let color: UIColor
}

/// Участник команды: исполнитель или автор задачи
struct Person {
    let id: String
    let firstName: String
    let lastName: String
    let color: UIColor

    var fullName: String { "\(firstName) \(lastName)" }
    var initials: String { "\(firstName.prefix(1))\(lastName.prefix(1))" }
}

enum TeamSample {
    static let people: [Person] = [
        Person(id: "anna", firstName: "Анна", lastName: "Смирнова",
               color: UIColor(red: 255 / 255, green: 149 / 255, blue: 0 / 255, alpha: 1)),
        Person(id: "ivan", firstName: "Иван", lastName: "Петров",
               color: UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1)),
        Person(id: "maria", firstName: "Мария", lastName: "Козлова",
               color: UIColor(red: 175 / 255, green: 82 / 255, blue: 222 / 255, alpha: 1)),
        Person(id: "dmitry", firstName: "Дмитрий", lastName: "Орлов",
               color: UIColor(red: 11 / 255, green: 166 / 255, blue: 134 / 255, alpha: 1)),
        Person(id: "elena", firstName: "Елена", lastName: "Соколова",
               color: UIColor(red: 255 / 255, green: 45 / 255, blue: 85 / 255, alpha: 1))
    ]

    /// Текущий пользователь — автор новых задач и комментариев
    static var me: Person { people[0] }
}

struct ChecklistItem {
    let id: String
    var title: String
    var isDone: Bool

    init(id: String = UUID().uuidString, title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

struct TaskAttachment {
    let id: String
    let name: String
    let date: Date

    init(id: String = UUID().uuidString, name: String, date: Date = Date()) {
        self.id = id
        self.name = name
        self.date = date
    }
}

struct TaskComment {
    let id: String
    let author: Person
    let text: String
    let date: Date
    let attachment: TaskAttachment?

    init(author: Person, text: String, date: Date = Date(), attachment: TaskAttachment? = nil) {
        self.id = UUID().uuidString
        self.author = author
        self.text = text
        self.date = date
        self.attachment = attachment
    }
}

struct TaskHistoryEvent {
    let text: String
    let author: Person
    let date: Date
}

struct BoardTask {
    let id: String
    var title: String
    var subtitle: String
    var tags: [TaskTag]
    var isFlagged: Bool
    var createdAt: Date
    var author: Person?
    var assignee: Person?
    var dueDate: Date?
    var checklist: [ChecklistItem]
    var comments: [TaskComment]
    var attachments: [TaskAttachment]
    var history: [TaskHistoryEvent]
    /// Идентификаторы связанных задач
    var links: [String]

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        tags: [TaskTag],
        isFlagged: Bool = false,
        createdAt: Date = Date(),
        author: Person? = TeamSample.me,
        assignee: Person? = nil,
        dueDate: Date? = nil,
        checklist: [ChecklistItem] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tags = tags
        self.isFlagged = isFlagged
        self.createdAt = createdAt
        self.author = author
        self.assignee = assignee
        self.dueDate = dueDate
        self.checklist = checklist
        self.comments = []
        self.attachments = []
        self.links = []
        self.history = author.map { [TaskHistoryEvent(text: "Создал(а) задачу", author: $0, date: createdAt)] } ?? []
    }

    mutating func record(_ text: String, by person: Person = TeamSample.me) {
        history.append(TaskHistoryEvent(text: text, author: person, date: Date()))
    }
}

struct BoardColumn {
    let title: String
    let tasks: [BoardTask]
    /// Свой цвет колонки, выбранный в «⋯». nil — колонка берёт цвет доски
    let customColor: UIColor?

    init(title: String, tasks: [BoardTask], color: UIColor? = nil) {
        self.title = title
        self.tasks = tasks
        self.customColor = color
    }

    /// Цвета, которые можно выбрать для колонки в меню «⋯»
    static let palette: [(title: String, color: UIColor)] = [
        ("Красный", .systemRed),
        ("Оранжевый", .systemOrange),
        ("Жёлтый", .systemYellow),
        ("Зелёный", .systemGreen),
        ("Мятный", .notesAccent),
        ("Бирюзовый", .systemTeal),
        ("Голубой", .systemCyan),
        ("Синий", .systemBlue),
        ("Индиго", .systemIndigo),
        ("Фиолетовый", .systemPurple),
        ("Розовый", .systemPink),
        ("Коричневый", .systemBrown),
        ("Серый", .systemGray)
    ]

    func with(tasks: [BoardTask]) -> BoardColumn {
        BoardColumn(title: title, tasks: tasks, color: customColor)
    }

    func with(customColor: UIColor?) -> BoardColumn {
        BoardColumn(title: title, tasks: tasks, color: customColor)
    }
}

struct Board {
    let id: String
    let title: String
    let symbolName: String
    let iconTop: UIColor
    let iconBottom: UIColor
    let columns: [BoardColumn]
    let emoji: String?

    init(
        id: String,
        title: String,
        symbolName: String,
        iconTop: UIColor,
        iconBottom: UIColor,
        columns: [BoardColumn],
        emoji: String? = nil
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.iconTop = iconTop
        self.iconBottom = iconBottom
        self.columns = columns
        self.emoji = emoji
    }

    func insertingTask(_ task: BoardTask, inColumn index: Int) -> Board {
        guard columns.indices.contains(index) else { return self }
        var next = columns
        var tasks = next[index].tasks
        tasks.insert(task, at: 0)
        next[index] = next[index].with(tasks: tasks)
        return with(columns: next)
    }

    func movingTask(inColumn columnIndex: Int, from source: Int, to destination: Int) -> Board {
        guard columns.indices.contains(columnIndex) else { return self }
        var tasks = columns[columnIndex].tasks
        guard tasks.indices.contains(source), tasks.indices.contains(destination) else { return self }
        tasks.insert(tasks.remove(at: source), at: destination)
        var next = columns
        next[columnIndex] = next[columnIndex].with(tasks: tasks)
        return with(columns: next)
    }

    /// Переносит задачу из одной колонки в другую (или внутри одной)
    func movingTask(
        fromColumn sourceColumn: Int, index sourceIndex: Int,
        toColumn destinationColumn: Int, index destinationIndex: Int
    ) -> Board {
        guard sourceColumn != destinationColumn else {
            return movingTask(inColumn: sourceColumn, from: sourceIndex, to: destinationIndex)
        }
        guard columns.indices.contains(sourceColumn), columns.indices.contains(destinationColumn),
              columns[sourceColumn].tasks.indices.contains(sourceIndex)
        else { return self }
        var next = columns
        var sourceTasks = next[sourceColumn].tasks
        let task = sourceTasks.remove(at: sourceIndex)
        var destinationTasks = next[destinationColumn].tasks
        destinationTasks.insert(task, at: min(max(destinationIndex, 0), destinationTasks.count))
        next[sourceColumn] = next[sourceColumn].with(tasks: sourceTasks)
        next[destinationColumn] = next[destinationColumn].with(tasks: destinationTasks)
        return with(columns: next)
    }

    // MARK: - Задачи по идентификатору

    func task(withID id: String) -> (column: Int, index: Int, task: BoardTask)? {
        for (columnIndex, column) in columns.enumerated() {
            if let index = column.tasks.firstIndex(where: { $0.id == id }) {
                return (columnIndex, index, column.tasks[index])
            }
        }
        return nil
    }

    var allTasks: [BoardTask] { columns.flatMap(\.tasks) }

    func replacingTask(_ task: BoardTask) -> Board {
        guard let found = self.task(withID: task.id) else { return self }
        var tasks = columns[found.column].tasks
        tasks[found.index] = task
        var next = columns
        next[found.column] = next[found.column].with(tasks: tasks)
        return with(columns: next)
    }

    func removingTask(id: String) -> Board {
        guard let found = task(withID: id) else { return self }
        var tasks = columns[found.column].tasks
        tasks.remove(at: found.index)
        var next = columns
        next[found.column] = next[found.column].with(tasks: tasks)
        return with(columns: next)
    }

    func insertingTask(_ task: BoardTask, inColumn columnIndex: Int, at index: Int) -> Board {
        guard columns.indices.contains(columnIndex) else { return self }
        var tasks = columns[columnIndex].tasks
        tasks.insert(task, at: min(max(index, 0), tasks.count))
        var next = columns
        next[columnIndex] = next[columnIndex].with(tasks: tasks)
        return with(columns: next)
    }

    /// Переносит задачу в конец другой колонки
    func movingTask(id: String, toColumn columnIndex: Int) -> Board {
        guard let found = task(withID: id), found.column != columnIndex,
              columns.indices.contains(columnIndex)
        else { return self }
        let removed = removingTask(id: id)
        return removed.insertingTask(found.task, inColumn: columnIndex, at: removed.columns[columnIndex].tasks.count)
    }

    func mapTasks(_ transform: (BoardTask, Int) -> BoardTask) -> Board {
        var counter = 0
        let next = columns.map { column in
            column.with(tasks: column.tasks.map { task in
                defer { counter += 1 }
                return transform(task, counter)
            })
        }
        return with(columns: next)
    }

    /// Цвет колонки: свой, если выбран, иначе — цвет доски
    func color(of column: BoardColumn) -> UIColor {
        column.customColor ?? iconBottom
    }

    func appendingColumn(_ column: BoardColumn) -> Board {
        with(columns: columns + [column])
    }

    func replacingColumn(at index: Int, with column: BoardColumn) -> Board {
        guard columns.indices.contains(index) else { return self }
        var next = columns
        next[index] = column
        return with(columns: next)
    }

    func movingColumn(from source: Int, to destination: Int) -> Board {
        guard columns.indices.contains(source), columns.indices.contains(destination) else { return self }
        var next = columns
        next.insert(next.remove(at: source), at: destination)
        return with(columns: next)
    }

    private func with(columns next: [BoardColumn]) -> Board {
        Board(
            id: id,
            title: title,
            symbolName: symbolName,
            iconTop: iconTop,
            iconBottom: iconBottom,
            columns: next,
            emoji: emoji
        )
    }

    var taskCount: Int {
        columns.reduce(0) { $0 + $1.tasks.count }
    }

    var flaggedTaskCount: Int {
        columns.reduce(0) { $0 + $1.tasks.filter(\.isFlagged).count }
    }
}

struct SidebarSmartCard {
    let id: String
    let title: String
    let editTitle: String
    let symbolName: String
    let topColor: UIColor
    let bottomColor: UIColor
    var count: String
    var isVisible: Bool
}

enum SidebarSmartCardSample {
    static let all: [SidebarSmartCard] = [
        SidebarSmartCard(
            id: "all",
            title: "Все задачи",
            editTitle: "Все задачи",
            symbolName: "tray.fill",
            // Фирменный зелёный приложения
            topColor: UIColor.notesAccent.lighter(by: 0.18),
            bottomColor: .notesAccent,
            count: "1",
            isVisible: true
        ),
        SidebarSmartCard(
            id: "flagged",
            title: "С флажком",
            editTitle: "С флажком",
            symbolName: "flag.fill",
            topColor: UIColor(red: 255 / 255, green: 172 / 255, blue: 64 / 255, alpha: 1),
            bottomColor: UIColor(red: 255 / 255, green: 149 / 255, blue: 0 / 255, alpha: 1),
            count: "0",
            isVisible: true
        ),
        SidebarSmartCard(
            id: "urgent",
            title: "Срочные",
            editTitle: "Срочные",
            symbolName: "alarm.fill",
            topColor: UIColor(red: 255 / 255, green: 214 / 255, blue: 10 / 255, alpha: 1),
            bottomColor: UIColor(red: 255 / 255, green: 184 / 255, blue: 0 / 255, alpha: 1),
            count: "0",
            isVisible: true
        ),
        SidebarSmartCard(
            id: "done",
            title: "Завершено",
            editTitle: "Завершено",
            symbolName: "checkmark",
            topColor: UIColor(red: 174 / 255, green: 174 / 255, blue: 178 / 255, alpha: 1),
            bottomColor: UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1),
            count: "0",
            isVisible: true
        ),
        SidebarSmartCard(
            id: "assigned",
            title: "Назначено",
            editTitle: "Назначено мне",
            symbolName: "person.fill",
            topColor: UIColor(red: 123 / 255, green: 232 / 255, blue: 154 / 255, alpha: 1),
            bottomColor: UIColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255, alpha: 1),
            count: "0",
            isVisible: false
        )
    ]
}

enum SidebarLayoutStore {
    private static let boardOrderKey = "sidebar.boardOrder"
    private static let smartCardsKey = "sidebar.smartCards"
    private static let customBoardsKey = "sidebar.customBoards"

    static func loadBoards() -> [Board] {
        let samples = BoardSample.all
        let custom = loadCustomBoards()
        var remaining = Dictionary(uniqueKeysWithValues: (samples + custom).map { ($0.id, $0) })
        guard let ids = UserDefaults.standard.stringArray(forKey: boardOrderKey) else {
            return samples + custom
        }
        var ordered: [Board] = []
        for id in ids {
            if let board = remaining.removeValue(forKey: id) {
                ordered.append(board)
            }
        }
        ordered.append(contentsOf: samples.filter { remaining[$0.id] != nil })
        ordered.append(contentsOf: custom.filter { remaining[$0.id] != nil })
        return ordered
    }

    static func saveBoards(_ boards: [Board]) {
        UserDefaults.standard.set(boards.map(\.id), forKey: boardOrderKey)
        let sampleIDs = Set(BoardSample.all.map(\.id))
        saveCustomBoards(boards.filter { !sampleIDs.contains($0.id) })
    }

    static func loadSmartCards() -> [SidebarSmartCard] {
        let defaults = SidebarSmartCardSample.all
        guard let stored = UserDefaults.standard.array(forKey: smartCardsKey) as? [[String: Any]] else {
            return defaults
        }
        var remaining = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        var ordered: [SidebarSmartCard] = []
        for item in stored {
            guard let id = item["id"] as? String, var card = remaining.removeValue(forKey: id) else { continue }
            if let visible = item["isVisible"] as? Bool {
                card.isVisible = visible
            }
            ordered.append(card)
        }
        ordered.append(contentsOf: defaults.filter { remaining[$0.id] != nil })
        return ordered
    }

    static func saveSmartCards(_ cards: [SidebarSmartCard]) {
        let payload: [[String: Any]] = cards.map { ["id": $0.id, "isVisible": $0.isVisible] }
        UserDefaults.standard.set(payload, forKey: smartCardsKey)
    }

    private static func loadCustomBoards() -> [Board] {
        guard let stored = UserDefaults.standard.array(forKey: customBoardsKey) as? [[String: Any]] else {
            return []
        }
        return stored.compactMap { item in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  let symbolName = item["symbolName"] as? String
            else { return nil }
            let emoji = item["emoji"] as? String
            func color(_ prefix: String, fallback: UIColor) -> UIColor {
                func component(_ key: String) -> CGFloat? {
                    (item[key] as? NSNumber).map { CGFloat(truncating: $0) }
                }
                guard let r = component(prefix + "R"),
                      let g = component(prefix + "G"),
                      let b = component(prefix + "B")
                else { return fallback }
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            }
            let fallback = UIColor.systemBlue
            return Board(
                id: id,
                title: title,
                symbolName: symbolName,
                iconTop: color("top", fallback: fallback),
                iconBottom: color("bottom", fallback: fallback),
                columns: [
                    BoardColumn(title: "Новые", tasks: []),
                    BoardColumn(title: "В работе", tasks: []),
                    BoardColumn(title: "На проверке", tasks: []),
                    BoardColumn(title: "Завершено", tasks: [])
                ],
                emoji: emoji
            )
        }
    }

    private static func saveCustomBoards(_ boards: [Board]) {
        let payload: [[String: Any]] = boards.map { board in
            var topR: CGFloat = 0, topG: CGFloat = 0, topB: CGFloat = 0, topA: CGFloat = 0
            var botR: CGFloat = 0, botG: CGFloat = 0, botB: CGFloat = 0, botA: CGFloat = 0
            board.iconTop.getRed(&topR, green: &topG, blue: &topB, alpha: &topA)
            board.iconBottom.getRed(&botR, green: &botG, blue: &botB, alpha: &botA)
            var item: [String: Any] = [
                "id": board.id,
                "title": board.title,
                "symbolName": board.symbolName,
                "topR": topR, "topG": topG, "topB": topB,
                "bottomR": botR, "bottomG": botG, "bottomB": botB
            ]
            if let emoji = board.emoji {
                item["emoji"] = emoji
            }
            return item
        }
        UserDefaults.standard.set(payload, forKey: customBoardsKey)
    }
}

enum BoardSample {
    static let tags = TagPalette()

    /// Примеры досок, дополненные авторами, исполнителями, сроками и чек-листами
    static let all: [Board] = rawBoards.enumerated().map { boardIndex, board in
        board.mapTasks { task, index in
            let people = TeamSample.people
            let seed = boardIndex * 7 + index
            var next = task
            next.author = people[seed % people.count]
            next.assignee = seed % 4 == 3 ? nil : people[(seed + 2) % people.count]
            next.createdAt = Calendar.current.date(byAdding: .day, value: -(seed % 9) - 1, to: Date()) ?? Date()
            next.dueDate = seed % 3 == 0 ? Calendar.current.date(byAdding: .day, value: seed % 10 + 2, to: Date()) : nil
            if seed % 2 == 0 {
                next.checklist = [
                    ChecklistItem(title: "Собрать требования", isDone: true),
                    ChecklistItem(title: "Согласовать с командой"),
                    ChecklistItem(title: "Проверить на iPad")
                ]
            }
            if let author = next.author {
                next.history = [TaskHistoryEvent(text: "Создал(а) задачу", author: author, date: next.createdAt)]
            }
            return next
        }
    }

    private static let rawBoards: [Board] = [
        Board(
            id: "mobile",
            title: "Design team",
            symbolName: "paintbrush.pointed.fill",
            iconTop: UIColor(red: 204 / 255, green: 115 / 255, blue: 255 / 255, alpha: 1),
            iconBottom: UIColor(red: 175 / 255, green: 82 / 255, blue: 222 / 255, alpha: 1),
            columns: [
                BoardColumn(title: "Новые", tasks: [
                    BoardTask(
                        title: "Добавить SSO через Okta в клиент iOS",
                        subtitle: "Нужен общий экран логина для TestFlight и прод-сборки.",
                        tags: [tags.ios, tags.backend],
                        isFlagged: true
                    ),
                    BoardTask(
                        title: "Покрыть редактор снапшот-тестами",
                        subtitle: "Сравнить вёрстку карточки заметки на iPhone и iPad.",
                        tags: [tags.qa, tags.ios]
                    ),
                    BoardTask(
                        title: "Описать флоу офлайн-синхронизации заметок",
                        subtitle: "Конфликт правок должен решаться на стороне API.",
                        tags: [tags.backend, tags.review]
                    )
                ]),
                BoardColumn(title: "В работе", tasks: [
                    BoardTask(
                        title: "Починить утечку памяти в текстовом редакторе",
                        subtitle: "Instruments показывает рост после вставки вложений.",
                        tags: [tags.ios, tags.urgent],
                        isFlagged: true
                    ),
                    BoardTask(
                        title: "Настроить CI для сборки TestFlight",
                        subtitle: "Подписать архив и выкладывать nightly на внутреннюю группу.",
                        tags: [tags.devops, tags.review]
                    )
                ]),
                BoardColumn(title: "На проверке", tasks: [
                    BoardTask(
                        title: "Проверить SSO на тестовом стенде",
                        subtitle: "Логин через Okta на iPad и iPhone перед релизом.",
                        tags: [tags.qa, tags.ios]
                    )
                ]),
                BoardColumn(title: "Завершено", tasks: [
                    BoardTask(
                        title: "Выкатить онбординг на новый экран заметок",
                        subtitle: "Проверили на iPad Air и iPhone 16, релиз в 1.4.",
                        tags: [tags.ios, tags.design]
                    ),
                    BoardTask(
                        title: "Обновить сертификаты push-уведомлений",
                        subtitle: "Новый Auth Key лежит в секретах репозитория.",
                        tags: [tags.devops]
                    )
                ])
            ]
        ),
        Board(
            id: "backend",
            title: "Backend и API",
            symbolName: "externaldrive.fill",
            iconTop: UIColor(red: 77 / 255, green: 163 / 255, blue: 255 / 255, alpha: 1),
            iconBottom: UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1),
            columns: [
                BoardColumn(title: "Новые", tasks: [
                    BoardTask(
                        title: "Спроектировать GraphQL для карточек досок",
                        subtitle: "Колонки и задачи должны приходить одним запросом.",
                        tags: [tags.backend, tags.review]
                    ),
                    BoardTask(
                        title: "Добавить rate limit на публичные вебхуки",
                        subtitle: "Сейчас интеграции Slack бьют лимиты при релизах.",
                        tags: [tags.backend, tags.urgent],
                        isFlagged: true
                    )
                ]),
                BoardColumn(title: "В работе", tasks: [
                    BoardTask(
                        title: "Мигрировать сессии пользователей на Redis",
                        subtitle: "Postgres не держит пик после открытия офиса.",
                        tags: [tags.backend, tags.devops],
                        isFlagged: true
                    ),
                    BoardTask(
                        title: "Написать контрактные тесты для /v2/notes",
                        subtitle: "Проверить пагинацию и вложения до выкладки клиента.",
                        tags: [tags.qa, tags.backend]
                    )
                ]),
                BoardColumn(title: "На проверке", tasks: [
                    BoardTask(
                        title: "Ревью контрактов /v2/notes",
                        subtitle: "Сверить схему ответа с клиентами iOS и веба.",
                        tags: [tags.backend, tags.review]
                    )
                ]),
                BoardColumn(title: "Завершено", tasks: [
                    BoardTask(
                        title: "Вынести поиск в отдельный Elasticsearch-кластер",
                        subtitle: "Индекс заметок больше не тормозит основную базу.",
                        tags: [tags.backend, tags.devops]
                    )
                ])
            ]
        ),
        Board(
            id: "infra",
            title: "Инфраструктура",
            symbolName: "cloud.fill",
            iconTop: UIColor(red: 100 / 255, green: 210 / 255, blue: 255 / 255, alpha: 1),
            iconBottom: UIColor(red: 50 / 255, green: 173 / 255, blue: 230 / 255, alpha: 1),
            columns: [
                BoardColumn(title: "Новые", tasks: [
                    BoardTask(
                        title: "Разнести staging и preview-окружения по кластерам",
                        subtitle: "Фича-ветки не должны делить Redis со staging.",
                        tags: [tags.devops]
                    ),
                    BoardTask(
                        title: "Добавить алерты по latency API в Grafana",
                        subtitle: "Порог 300 мс на /v2/boards, дежурный в Slack.",
                        tags: [tags.devops, tags.urgent],
                        isFlagged: true
                    )
                ]),
                BoardColumn(title: "В работе", tasks: [
                    BoardTask(
                        title: "Перевести сборки на GitHub Actions runners",
                        subtitle: "Самохосты в офисе падают во время iOS-архива.",
                        tags: [tags.devops, tags.review]
                    )
                ]),
                BoardColumn(title: "На проверке", tasks: [
                    BoardTask(
                        title: "Проверить алерты Grafana на стейдже",
                        subtitle: "Нагрузить /v2/boards и убедиться, что дежурный получит сигнал.",
                        tags: [tags.devops, tags.qa]
                    )
                ]),
                BoardColumn(title: "Завершено", tasks: [
                    BoardTask(
                        title: "Включить шифрование дисков на продовых нодах",
                        subtitle: "Ключи ротации лежат в Vault, проверка в runbook.",
                        tags: [tags.devops]
                    ),
                    BoardTask(
                        title: "Обновить Terraform-модули VPC",
                        subtitle: "Новые сабнеты для GitHub runners уже в проде.",
                        tags: [tags.devops, tags.review]
                    )
                ])
            ]
        ),
        Board(
            id: "design-system",
            title: "Дизайн-система",
            symbolName: "square.grid.2x2.fill",
            // Фирменный зелёный интерфейса
            iconTop: UIColor.notesAccent.lighter(by: 0.18),
            iconBottom: .notesAccent,
            columns: [
                BoardColumn(title: "Новые", tasks: [
                    BoardTask(
                        title: "Собрать токены отступов для iPad-лейаутов",
                        subtitle: "Нужны значения для сайдбара 320 и колонок канбана.",
                        tags: [tags.design, tags.ios]
                    ),
                    BoardTask(
                        title: "Описать состояния пустых колонок канбана",
                        subtitle: "Что показывать, если в «Новых» ещё нет задач.",
                        tags: [tags.design]
                    )
                ]),
                BoardColumn(title: "В работе", tasks: [
                    BoardTask(
                        title: "Сверстать набор тегов для карточек задач",
                        subtitle: "Цветные капсулы должны читаться на сером фоне.",
                        tags: [tags.design, tags.ios]
                    ),
                    BoardTask(
                        title: "Согласовать зелёный акцент с тёмной темой",
                        subtitle: "Проверить контраст кнопок «Новая задача».",
                        tags: [tags.design, tags.review],
                        isFlagged: true
                    )
                ]),
                BoardColumn(title: "На проверке", tasks: [
                    BoardTask(
                        title: "Ревью токенов цветов для тёмной темы",
                        subtitle: "Контраст тегов и кнопок на сером фоне доски.",
                        tags: [tags.design, tags.review]
                    )
                ]),
                BoardColumn(title: "Завершено", tasks: [
                    BoardTask(
                        title: "Зафиксировать иконки SF Symbols для сайдбара",
                        subtitle: "Четыре аватара досок уже в макете Настроек.",
                        tags: [tags.design, tags.ios]
                    )
                ])
            ]
        )
    ]

    static var initial: Board { all[0] }
}

/// Все теги: стандартные и созданные пользователем
enum TagLibrary {
    static var custom: [TaskTag] = []

    static var all: [TaskTag] {
        let palette = TagPalette()
        return [palette.ios, palette.backend, palette.qa, palette.urgent, palette.review, palette.devops, palette.design] + custom
    }

    /// Цвета для новых тегов
    static let colors: [UIColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemMint,
        .systemTeal, .systemBlue, .systemIndigo, .systemPurple, .systemPink, .systemBrown, .systemGray
    ]
}

struct TagPalette {
    let ios = TaskTag(
        title: "iOS",
        color: UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1)
    )
    let backend = TaskTag(
        title: "Backend",
        color: UIColor(red: 88 / 255, green: 86 / 255, blue: 214 / 255, alpha: 1)
    )
    let qa = TaskTag(
        title: "QA",
        color: UIColor(red: 255 / 255, green: 149 / 255, blue: 0 / 255, alpha: 1)
    )
    let urgent = TaskTag(
        title: "Срочно",
        color: UIColor(red: 255 / 255, green: 59 / 255, blue: 48 / 255, alpha: 1)
    )
    let review = TaskTag(
        title: "Review",
        color: UIColor(red: 11 / 255, green: 166 / 255, blue: 134 / 255, alpha: 1)
    )
    let devops = TaskTag(
        title: "DevOps",
        color: UIColor(red: 50 / 255, green: 173 / 255, blue: 230 / 255, alpha: 1)
    )
    let design = TaskTag(
        title: "Дизайн",
        color: UIColor(red: 255 / 255, green: 45 / 255, blue: 85 / 255, alpha: 1)
    )
}
