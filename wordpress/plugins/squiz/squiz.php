<?php
/**
 * Plugin Name: Squiz
 * Version: 2.5.0
 * Author: Martin Reed <martin@martinreed.co.uk>
 * Description: Rails-driven asset registry with classic WordPress UI support.
 */

if (!defined('ABSPATH')) exit;

class Squiz {

    public static function boot() {
        add_action('rest_api_init', [__CLASS__, 'register_meta']);
        add_action('rest_api_init', [__CLASS__, 'register_routes']);
        add_action('add_meta_boxes', [__CLASS__, 'register_page_meta_box']);
        add_action('add_meta_boxes_attachment', [__CLASS__, 'register_attachment_meta_box']);
        add_action('generate_after_header', [__CLASS__, 'render_after_masthead']);
        add_action('wp_enqueue_scripts', [__CLASS__, 'add_styles']);
    }

    /**
     * -------------------------------------------------------
     * META STORAGE (SAFE + REST EXPOSED)
     * -------------------------------------------------------
     */
    public static function register_meta() {

        $args = [
            'description'      => 'Squiz Asset #',
            'type'             => 'integer',
            'single'           => true,
            'show_in_rest'     => true,
            'sanitize_callback'=> function($v) {
              return (is_numeric($v) && $v > 0) ? (int) $v : null;
            },
            'auth_callback'    => self::can_edit(),
        ];
        register_post_meta('post', 'assetid', $args);
        register_post_meta('page', 'assetid', $args);
        register_post_meta('attachment', 'assetid', $args);

        $args = [
            'description'      => 'Squiz Breadcrumbs',
            'type'             => 'string',
            'single'           => true,
            'show_in_rest'     => true,
            'auth_callback'    => self::can_edit(),
        ];
        register_post_meta('post', 'breadcrumbs', $args);
        register_post_meta('page', 'breadcrumbs', $args);
    }

    /**
     * -------------------------------------------------------
     * REST API (Rails writes only)
     * -------------------------------------------------------
     */
    public static function register_routes() {

        register_rest_route('squiz/v2', '/asset_meta', [
            'methods'  => 'POST',
            'callback' => [__CLASS__, 'set_asset_meta'],
            'permission_callback' => [__CLASS__, 'can_edit'],
        ]);

        register_rest_route('squiz/v2', '/asset/(?P<assetid>\d+)', [
            'methods'  => 'GET',
            'callback' => [__CLASS__, 'lookup'],
            'permission_callback' => '__return_true'
        ]);
    }

    public static function can_edit() {
        return current_user_can('edit_posts');
    }

    public static function set_asset_meta($request) {
        $post_id = (int) $request['post_id'];
        $assetid = (int) $request['assetid'];

        if (!$post_id || !$assetid) {
            return new WP_REST_Response(['error' => 'invalid_request'], 400);
        }

        if ($assetid <= 0) {
            return new WP_REST_Response(['error' => 'invalid_assetid'], 400);
        }

        if (!get_post($post_id)) {
            return new WP_REST_Response(['error' => 'post_not_found'], 404);
        }

        $existing = get_post_meta($post_id, 'assetid', true);
        if ((string) $existing !== (string) $assetid) {
            $written = update_post_meta($post_id, 'assetid', $assetid);

            if ($written === false) {
                error_log("update_post_meta failed");
                return new WP_REST_Response([
                    'ok' => false,
                    'error' => 'set_asset_meta_update_failed'
                ], 500);
            }
        }

        $updated_meta = [];
        $rejected_meta = [];

        $additional_meta = $request->get_param('additional_meta');

        if (is_array($additional_meta)) {
            foreach ($additional_meta as $key => $value) {
                $meta_key = sanitize_key($key);

                if (!self::is_registered_meta_key($meta_key, $post_id)) {
                    $rejected_meta[$meta_key] = 'Meta field is not registered';
                    continue;
                }

                update_post_meta($post_id, $meta_key, wp_kses_post($value));
                $updated_meta[$meta_key] = true;
            }
        }

        return [
            'ok'            => true,
            'post_id'       => $post_id,
            'assetid'       => $assetid,
            'updated_meta'  => $updated_meta,
            'rejected_meta' => $rejected_meta,
        ];
    }

    public static function set_asset($request) {

        $post_id = (int) $request['post_id'];
        $assetid = (int) $request['assetid'];

        if (!$post_id) {
            return new WP_REST_Response(['error' => 'Missing post_id'], 400);
        }

        if (!get_post($post_id)) {
            return new WP_REST_Response(['error' => 'Post not found'], 404);
        }

        update_post_meta($post_id, 'assetid', $assetid);

        $updated_meta = [];
        $rejected_meta = [];

        $additional_meta = $request->get_param('additional_meta');

        if (is_array($additional_meta)) {
            foreach ($additional_meta as $key => $value) {
                $meta_key = sanitize_key($key);

                if (!self::is_registered_meta_key($meta_key, $post_id)) {
                    $rejected_meta[$meta_key] = 'Meta field is not registered';
                    continue;
                }

                update_post_meta($post_id, $meta_key, wp_kses_post($value));
                $updated_meta[$meta_key] = true;
            }
        }

        return [
            'success'       => true,
            'post_id'       => $post_id,
            'assetid'       => $assetid,
            'updated_meta'  => $updated_meta,
            'rejected_meta' => $rejected_meta,
        ];
    }


    static function is_registered_meta_key($meta_key, $post_id) {

        $post = get_post($post_id);

        if (!$post) {
            return false;
        }

        $registered = get_registered_meta_keys('post', $post->post_type);

        return array_key_exists($meta_key, $registered);
    }

    /**
     * -------------------------------------------------------
     * CLASSIC ADMIN UI - PAGES
     * -------------------------------------------------------
     */
    public static function register_page_meta_box() {

        add_meta_box(
            'squiz_assetid_page',
            'Squiz',
            [__CLASS__, 'render_meta_box'],
            'page',
            'side'
        );
    }

    /**
     * -------------------------------------------------------
     * CLASSIC ADMIN UI - MEDIA ATTACHMENTS
     * -------------------------------------------------------
     */
    public static function register_attachment_meta_box() {

        add_meta_box(
            'squiz_assetid_attachment',
            'Squiz',
            [__CLASS__, 'render_meta_box'],
            'attachment',
            'side'
        );
    }

    /**
     * -------------------------------------------------------
     * RENDER FIELD (READ-ONLY)
     * -------------------------------------------------------
     */
    public static function render_meta_box($post) {

        echo '<p style="font-size:11px;color:#666;margin-top:6px;">Managed externally</p>';
        $assetid = (int) get_post_meta($post->ID, 'assetid', true);
        self::render_meta_field($assetid, 'Asset #', 'number');
        $breadcrumbs = get_post_meta($post->ID, 'breadcrumbs', true);
        self::render_meta_field($breadcrumbs, 'Breadcrumbs', 'text');
    }

    static function render_meta_field($value, $title, $type) {
        echo '<label style="font-weight:600;">' . $title . '</label>';
        echo '<input type="' . $type . '" readonly style="width:100%;margin-top:5px;" value="' . esc_attr($value) . '">';

    }

    /**
     * -------------------------------------------------------
     * DISPLAY BREADCRUMBS
     * -------------------------------------------------------
     */
    public static function render_after_masthead() {
        if (!is_page()) {
            return;
        }

        $json = get_post_meta(get_the_ID(), 'breadcrumbs', true);

        if (!$json) {
            return;
        }

error_log('render_after_masthead json' . $json);
        $slugs = json_decode($json, true);

        if (!is_array($slugs)) {
            error_log('[squiz-breadcrumbs] Invalid breadcrumbs JSON for page ' . get_the_ID());
            return;
        }

        $links = [];

        foreach ($slugs as $slug) {
            $slug = sanitize_title($slug);

            if (!$slug) {
                continue;
            }

            $page = get_page_by_path($slug, OBJECT, 'page');

            if (!$page) {
                error_log('[squiz-breadcrumbs] Breadcrumb page not found for slug: ' . $slug);
                continue;
            }

            $links[] = sprintf(
                '<a href="%s">%s</a>',
                esc_url(get_permalink($page->ID)),
                esc_html(get_the_title($page->ID))
            );
        }

        if (!$links) {
            return;
        }

        echo '<div id="breadcrumbs" class="squiz-breadcrumbs">';
        echo implode('<span class="squiz-breadcrumbs-separator"> &raquo; </span>', $links);
        echo '</div>';
    }

    public static function add_styles() {
        wp_add_inline_style(
            'generate-style',
            '
            .squiz-breadcrumbs {
                background: #f2e9d3;
                padding: 8px 20px;
                font-size: 14px;
                line-height: 20px;
            }

            .squiz-breadcrumbs a {
                color: #0086B2;
                text-decoration: none;
            }

            .squiz-breadcrumbs a:hover {
                color: #00A6DC;
                border-bottom: 1px dotted #0086B2;
            }

            .squiz-breadcrumbs-separator {
                margin: 0 6px;
                color: #666;
            }
            '
        );
    }

}

/**
 * -------------------------------------------------------
 * BOOT STRAP (SAFE)
 * -------------------------------------------------------
 */
add_action('plugins_loaded', ['Squiz', 'boot']);
