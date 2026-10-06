import atlas/id
import gleam/string

pub fn generates_valid_ids_test() {
  assert id.is_valid(id.generate(fn(_) { 0 }))
  assert id.is_valid(id.generate(fn(n) { n - 1 }))
  assert id.generate(fn(_) { 0 }) == "aaaaaaaaaaaaaaa"
  assert string.length(id.generate(fn(_) { 5 })) == 15
}

pub fn uses_the_whole_alphabet_test() {
  // Counting from 0 to 35 reaches the last letter and digits.
  let counter = fn(n) { n - 1 }
  assert id.generate(counter) == "999999999999999"
  assert id.generate(fn(n) { n / 2 }) == "sssssssssssssss"
}

pub fn validation_test() {
  assert id.is_valid("abc123def456ghi")
  assert !id.is_valid("")
  assert !id.is_valid("abc123def456gh")
  assert !id.is_valid("abc123def456ghij")
  assert !id.is_valid("ABC123def456ghi")
  assert !id.is_valid("abc123def456gh-")
  assert !id.is_valid("abc123def456gh ")
}
