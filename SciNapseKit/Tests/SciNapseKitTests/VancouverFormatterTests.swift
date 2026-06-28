// SciNapseKit/Tests/SciNapseKitTests/VancouverFormatterTests.swift
import XCTest
@testable import SciNapseKit

final class VancouverFormatterTests: XCTestCase {
    func test_standardArticle() {
        let m = ResolvedMetadata(title: "Solid-organ transplantation in HIV-infected patients",
                                 authors: ["Halpern SD", "Ubel PA", "Caplan AL"],
                                 journal: "N Engl J Med", year: 2002, month: "Jul", day: 25,
                                 volume: "347", issue: "4", pages: "284-287",
                                 doi: "10.1056/nejm200207253470409")
        let out = VancouverFormatter.format(m)
        XCTAssertEqual(out, "Halpern SD, Ubel PA, Caplan AL. Solid-organ transplantation in HIV-infected patients. N Engl J Med. 2002 Jul 25;347(4):284-7. https://doi.org/10.1056/nejm200207253470409")
    }
    func test_sevenAuthors_etAl() {
        let authors = (1...7).map { "Author\($0) AB" }
        let m = ResolvedMetadata(title: "T", authors: authors, journal: "J", year: 2020)
        let out = VancouverFormatter.format(m)
        XCTAssertTrue(out.hasPrefix("Author1 AB, Author2 AB, Author3 AB, Author4 AB, Author5 AB, Author6 AB, et al."))
    }
    func test_noAuthor_startsWithTitle() {
        let m = ResolvedMetadata(title: "Anon report", authors: [], journal: "Health News", year: 2005)
        XCTAssertTrue(VancouverFormatter.format(m).hasPrefix("Anon report."))
    }
    func test_noVolume_pagesAfterColon() {
        let m = ResolvedMetadata(title: "T", authors: ["X Y"], journal: "J", year: 1995, pages: "5")
        XCTAssertTrue(VancouverFormatter.format(m).contains("1995:5."))
    }
    func test_abbreviatePages() {
        XCTAssertEqual(VancouverFormatter.abbreviatePages(start: "284", end: "287"), "7")
        XCTAssertEqual(VancouverFormatter.abbreviatePages(start: "1432", end: "1440"), "40")
        XCTAssertEqual(VancouverFormatter.abbreviatePages(start: "198", end: "204"), "204")
    }
}
