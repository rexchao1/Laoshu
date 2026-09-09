import Testing
@testable import LaoshuKit

@Test func testDefinitionCleanup() {
    #expect(CatalogueBuilder.cleanDefinition(
        "only have ...; there is only .../(used in combination with 才[cai2]) it is only if ... (that one can ...) (as in 只有通過治療才能痊愈|只有通过治疗才能痊愈[zhi3 you3 tong1 guo4 zhi4 liao2 cai2 neng2 quan2 yu4] \"the only way to cure it is with therapy\")/it is only (someone) who ... (as in 只有男性才有此需要[zhi3 you3 nan2 xing4 cai2 you3 ci3 xu1 yao4] \"only men would have such a requirement\")/(used to express lack of alternatives) can only; have no choice but to (as in 只有屈服[zhi3 you3 qu1 fu2] \"the only thing you can do is give in\")"
    ) == "only have ...; there is only ...")

    #expect(CatalogueBuilder.cleanDefinition(
        "a semantically light, transitive verb that is combined with various grammatical objects to form compound verbs and verb-object phrases with a diverse range of meanings (e.g. 打傘|打伞[da3 san3] \"to hold an umbrella\", 打電話|打电话[da3 dian4 hua4] \"to make a phone call\", 打針|打针[da3 zhen1] \"to get an injection\", 打手套[da3 shou3 tao4] \"to knit gloves\", 打氣|打气[da3 qi4] \"to inflate\")/to hit; to strike/to fight/(coll.) from; since (as in 打那以後|打那以后[da3 na4 yi3 hou4] \"since then\")"
    ) == "a semantically light, transitive verb that is combined with various grammatical...")

    #expect(CatalogueBuilder.cleanDefinition(
        "apart from; besides; in addition to (used to exclude, as in 除了他，誰也沒來|除了他，谁也没来[chu2 le5 ta1 , shei2 ye3 mei2 lai2] \"apart from him, nobody came\", or to include, as in 除了英語，他也會法語|除了英语，他也会法语[chu2 le5 Ying1 yu3 , ta1 ye3 hui4 Fa3 yu3] \"in addition to English, he also knows French\")/(used to introduce one of two habitual alternatives in the pattern 除了[chu2 le5] + A + 就是[jiu4 shi4] + B, \"either A or B\")"
    ) == "apart from; besides; in addition to")

    // The whole first sense is a parenthetical carrying a CJK example, so it
    // disappears entirely and the second sense leads.
    #expect(CatalogueBuilder.cleanDefinition(
        "(prefix indicating ordinal number, as in 第六[di4 liu4] \"sixth\")/(literary) grades in which successful candidates in the imperial examinations were placed/(old) residence of a high official/(literary) but; however/(literary) only; just"
    ) == "(literary) grades in which successful candidates in the imperial examinations were placed")

    // No `/`-clause, no parenthetical, under both length limits: passes through unchanged.
    #expect(CatalogueBuilder.cleanDefinition(
        "classifier indicating a small amount or small number greater than 1: some, a few, several"
    ) == "classifier indicating a small amount or small number greater than 1: some, a few, several")

    // Bracketed pinyin outside of parentheses is left alone; only a
    // parenthetical containing CJK or `[pinyin]` is stripped.
    #expect(CatalogueBuilder.cleanDefinition(
        "four seasons, namely: spring 春[chun1], summer 夏[xia4], autumn 秋[qiu1] and winter 冬[dong1]"
    ) == "four seasons, namely: spring 春[chun1], summer 夏[xia4], autumn 秋[qiu1] and winter 冬[dong1]")
}

@Test func testSuffixStrip() {
    #expect(CatalogueBuilder.stripSuffix("打1") == "打")
    #expect(CatalogueBuilder.stripSuffix("的地得3") == "的地得")
    #expect(CatalogueBuilder.stripSuffix("爱") == "爱")
}

@Test func testCollapseKeepsLowestLevel() {
    let rows = [
        CatalogueBuilder.SourceRow(
            wordIndex: 42, level: 3, word: "打1", pinyin: "dǎ",
            pinyinNumbered: "da3", definition: "to hit"
        ),
        CatalogueBuilder.SourceRow(
            wordIndex: 42, level: 1, word: "打1", pinyin: "dǎ",
            pinyinNumbered: "da3", definition: "to hit"
        ),
        CatalogueBuilder.SourceRow(
            wordIndex: 7, level: 2, word: "些", pinyin: "xiē",
            pinyinNumbered: "xie1", definition: "a few"
        ),
    ]

    let collapsed = CatalogueBuilder.collapse(rows)
    #expect(collapsed.count == 2)
    #expect(collapsed.first(where: { $0.wordIndex == 42 })?.level == 1)
    #expect(collapsed.first(where: { $0.wordIndex == 7 })?.level == 2)
}

// MARK: - Gloss validation

@Test func testValidateGlossAcceptsAnOrdinaryGloss() throws {
    try CatalogueBuilder.validateGloss("to love; to be fond of", wordIndex: 1)
}

@Test func testValidateGlossAcceptsBareSurname() throws {
    try CatalogueBuilder.validateGloss("surname; family name", wordIndex: 1)
}

@Test func testValidateGlossRejectsEmptyGloss() {
    #expect(throws: CatalogueBuilder.BuildError.emptyGloss(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsGlossOver40Characters() {
    let gloss = String(repeating: "a", count: 41)
    #expect(throws: CatalogueBuilder.BuildError.glossTooLong(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss(gloss, wordIndex: 1)
    }
}

@Test func testValidateGlossAcceptsExactly40Characters() throws {
    let gloss = String(repeating: "a", count: 40)
    try CatalogueBuilder.validateGloss(gloss, wordIndex: 1)
}

@Test func testValidateGlossRejectsSurnameFollowedByCapitalizedWord() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("cold; surname Leng", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsVariantOf() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("variant of 打", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsOldVariantOf() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("old variant of 打", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsErhuaVariantOf() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("erhua variant of 打", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsAbbrFor() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("abbr. for something", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsBoundForm() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("(bound form) to eat", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsHanzi() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("to hit 打", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsBracketedPinyinReference() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("to hold an umbrella [da3 san3]", wordIndex: 1)
    }
}

@Test func testValidateGlossRejectsTrailingEllipsis() {
    #expect(throws: CatalogueBuilder.BuildError.bannedGlossPattern(wordIndex: 1)) {
        try CatalogueBuilder.validateGloss("a semantically light, transitive verb...", wordIndex: 1)
    }
}

@Test func testBuildGlossMapRejectsUnknownWordIndex() {
    #expect(throws: CatalogueBuilder.BuildError.unknownGlossWordIndex(wordIndex: 99)) {
        try CatalogueBuilder.buildGlossMap(fromLines: ["99\tto hit"], wordIndices: [1])
    }
}

@Test func testBuildGlossMapRejectsDuplicateWordIndex() {
    #expect(throws: CatalogueBuilder.BuildError.duplicateGlossWordIndex(wordIndex: 1)) {
        try CatalogueBuilder.buildGlossMap(fromLines: ["1\tto hit", "1\tto strike"], wordIndices: [1])
    }
}

@Test func testBuildGlossMapRejectsMissingGloss() {
    #expect(throws: CatalogueBuilder.BuildError.missingGloss(wordIndex: 2)) {
        try CatalogueBuilder.buildGlossMap(fromLines: ["1\tto hit"], wordIndices: [1, 2])
    }
}

@Test func testBuildGlossMapRejectsMalformedLine() {
    #expect(throws: CatalogueBuilder.BuildError.malformedGlossLine(lineNumber: 2)) {
        try CatalogueBuilder.buildGlossMap(fromLines: ["not-a-tsv-row"], wordIndices: [1])
    }
}

@Test func testBuildGlossMapAcceptsAValidFile() throws {
    let glosses = try CatalogueBuilder.buildGlossMap(
        fromLines: ["1\tto hit", "2\ta few"],
        wordIndices: [1, 2]
    )
    #expect(glosses == [1: "to hit", 2: "a few"])
}
