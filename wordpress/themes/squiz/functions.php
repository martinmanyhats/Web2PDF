<?php

add_action('wp_enqueue_scripts', function () {
    wp_enqueue_style(
        'generatepress-parent',
        get_template_directory_uri() . '/style.css'
    );

    wp_enqueue_style(
        'squiz-style',
        get_stylesheet_uri(),
        ['generatepress-parent'],
        wp_get_theme()->get('Version')
    );
});
