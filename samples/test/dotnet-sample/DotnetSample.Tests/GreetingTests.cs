using FluentAssertions;
using Xunit;

namespace DotnetSample.Tests;

public class GreetingTests
{
    [Theory]
    [InlineData(1, "1 item")]
    [InlineData(2, "2 items")]
    [InlineData(0, "0 items")]
    public void ToQuantity_humanizes_item_counts(int count, string expected)
    {
        Greeting.ToQuantity(count).Should().Be(expected);
    }

    [Theory]
    [InlineData(1, "1st")]
    [InlineData(2, "2nd")]
    [InlineData(3, "3rd")]
    [InlineData(11, "11th")]
    public void Ordinalize_returns_ordinal_form(int count, string expected)
    {
        Greeting.Ordinalize(count).Should().Be(expected);
    }

    [Fact]
    public void ToWords_spells_out_numbers()
    {
        Greeting.ToWords(5).Should().Be("five");
    }
}
