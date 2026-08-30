using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// What a document calls itself, in the three places it might say so and in the order they are
/// believed: front matter, first heading, file name.
/// </summary>
public class MarkdownDocumentTitleTests
{
    private const string FileName = "quarterly-review";

    private static string Resolve(string markdown) => MarkdownDocumentTitle.Resolve(markdown, FileName);

    [Fact]
    public void FrontMatterIsBelievedFirst()
    {
        Assert.Equal("Quarterly Review", Resolve("""
            ---
            title: Quarterly Review
            author: Somebody
            ---

            # A Heading Nobody Should Prefer
            """));
    }

    [Theory]
    [InlineData("title: Quarterly Review")]
    [InlineData("title:    Quarterly Review")]
    [InlineData("title: \"Quarterly Review\"")]
    [InlineData("title: 'Quarterly Review'")]
    [InlineData("Title: Quarterly Review")]
    public void AFrontMatterTitleIsReadWithOrWithoutQuotes(string line)
    {
        Assert.Equal("Quarterly Review", Resolve($"---\n{line}\n---\n\nBody\n"));
    }

    /// <summary>A closing <c>...</c> is as good as a closing <c>---</c>.</summary>
    [Fact]
    public void AFrontMatterBlockMayEndWithTheOtherYamlTerminator()
    {
        Assert.Equal("Quarterly Review", Resolve("---\ntitle: Quarterly Review\n...\n\n# Other\n"));
    }

    /// <summary>An indented key belongs to something nested, not to the document.</summary>
    [Fact]
    public void AnIndentedTitleKeyIsNotTheDocumentsTitle()
    {
        Assert.Equal("Real Heading", Resolve("---\nbook:\n  title: Chapter Title\n---\n\n# Real Heading\n"));
    }

    /// <summary>
    /// Front matter without a title must not be mistaken for content: the block is skipped before the
    /// heading is looked for, so what follows it is what answers.
    /// </summary>
    [Fact]
    public void FrontMatterWithoutATitleFallsThroughToTheHeading()
    {
        Assert.Equal("Real Heading", Resolve("---\nauthor: Somebody\n---\n\n# Real Heading\n"));
    }

    /// <summary>An unterminated block is not front matter at all; the document is Markdown from the top.</summary>
    [Fact]
    public void AnUnterminatedFrontMatterBlockIsNotFrontMatter()
    {
        Assert.Equal(FileName, Resolve("---\ntitle: Never Closed\n\nBody text\n"));
    }

    [Fact]
    public void TheFirstLevelOneHeadingIsUsedWhenThereIsNoFrontMatter()
    {
        Assert.Equal("Quarterly Review", Resolve("Some preamble.\n\n# Quarterly Review\n\n# Later Heading\n"));
    }

    /// <summary>A setext heading is a level-one heading too.</summary>
    [Fact]
    public void ASetextHeadingCounts()
    {
        Assert.Equal("Quarterly Review", Resolve("Quarterly Review\n================\n\nBody\n"));
    }

    /// <summary>
    /// A running head is a line of type, so the heading contributes its text and none of its markup.
    /// </summary>
    [Fact]
    public void AHeadingsMarkupIsNotPartOfTheTitle()
    {
        Assert.Equal("Q3 Review of tiger-mark", Resolve("# Q3 *Review* of `tiger-mark`\n"));
    }

    [Fact]
    public void ALinkedHeadingContributesItsText()
    {
        Assert.Equal("Quarterly Review", Resolve("# [Quarterly Review](https://example.invalid)\n"));
    }

    /// <summary>
    /// Only a real parse can tell a heading from a comment in a shell script somebody quoted, which is
    /// why the search is Markdig's and not a match on a leading hash.
    /// </summary>
    [Fact]
    public void AHashInsideAFencedCodeBlockIsNotAHeading()
    {
        Assert.Equal(FileName, Resolve("```sh\n# Not a heading\necho hello\n```\n"));
    }

    /// <summary>Deeper headings are not the document's title; a section is not the document.</summary>
    [Fact]
    public void ALevelTwoHeadingIsNotTheTitle()
    {
        Assert.Equal(FileName, Resolve("## A Section\n\nBody\n"));
    }

    /// <summary>A heading that wrapped in the source prints as one line.</summary>
    [Fact]
    public void AWrappedHeadingIsCollapsedToOneLine()
    {
        Assert.Equal("A Long Title That Wrapped", Resolve("A Long Title\nThat Wrapped\n============\n"));
    }

    [Theory]
    [InlineData("")]
    [InlineData("Just a paragraph.\n")]
    [InlineData("#\n")]
    public void WithoutFrontMatterOrAHeadingTheFileNameIsTheTitle(string markdown)
    {
        Assert.Equal(FileName, Resolve(markdown));
    }

    /// <summary>Resolution always answers, even when it has been given nothing to answer with.</summary>
    [Fact]
    public void NothingAtAllStillResolvesToSomething()
    {
        Assert.Equal(string.Empty, MarkdownDocumentTitle.Resolve(null, null));
    }
}
