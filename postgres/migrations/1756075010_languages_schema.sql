-- schema: language codes used for cue content and learning profiles
create schema if not exists languages;
grant usage on schema languages to authenticated;

create domain languages.language_code as text
    check (value in ('en','de','fr'));
