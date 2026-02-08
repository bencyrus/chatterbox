-- add spanish (es) as a supported language

-- widen the language_code domain to include es
alter domain languages.language_code
    drop constraint language_code_check;

alter domain languages.language_code
    add constraint language_code_check
    check (value in ('en','de','fr','zh','es'));

-- update the available language codes config to include es
update internal.config
set value = '["en","fr","de","zh","es"]'
where key = 'available_language_codes';
