-- add mandarin (zh) as a supported language

-- widen the language_code domain to include zh
alter domain languages.language_code
    drop constraint language_code_check;

alter domain languages.language_code
    add constraint language_code_check
    check (value in ('en','de','fr','zh'));

-- update the available language codes config to include zh
update internal.config
set value = '["en","fr","de","zh"]'
where key = 'available_language_codes';
