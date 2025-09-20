namespace FamousQuotes.Api.Models;

public record Quote(int Id, string Text, string? Author, string? Source, DateTime CreatedAt);