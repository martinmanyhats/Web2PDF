<?php
/**
 * Plugin Name: Squiz
 * Version: 2.4.0
 * Author: Martin Reed <martin@martinreed.co.uk>
 * Description: Rails-driven asset registry with classic WordPress UI support.
 */

if (!defined('ABSPATH')) exit;

class Squiz {

    public static function boot() {
        add_action('init', [__CLASS__, 'register_meta']);
        add_action('rest_api_init', [__CLASS__, 'register_routes']);
        add_action('add_meta_boxes', [__CLASS__, 'register_page_meta_box']);
        add_action('add_meta_boxes_attachment', [__CLASS__, 'register_attachment_meta_box']);
    }

    /**
     * -------------------------------------------------------
     * META STORAGE (SAFE + REST EXPOSED)
     * -------------------------------------------------------
     */
    public static function register_meta() {

        register_meta('post', 'assetid', [
            'object_subtype'   => 'page',
            'type'             => 'integer',
            'single'           => true,
            'show_in_rest'     => true,
            'sanitize_callback'=> [__CLASS__, 'sanitize_assetid'],
        ]);

        register_meta('post', 'assetid', [
            'object_subtype'   => 'attachment',
            'type'             => 'integer',
            'single'           => true,
            'show_in_rest'     => true,
            'sanitize_callback'=> [__CLASS__, 'sanitize_assetid'],
        ]);
    }

    public static function sanitize_assetid($value) {
        return is_numeric($value) ? (int) $value : null;
    }

    /**
     * -------------------------------------------------------
     * REST API (Rails writes only)
     * -------------------------------------------------------
     */
    public static function register_routes() {

        register_rest_route('squiz/v2', '/asset', [
            'methods'  => 'POST',
            'callback' => [__CLASS__, 'set_assetid'],
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

    public static function set_assetid($request) {

        $post_id = (int) $request['post_id'];
        $assetid = (int) $request['assetid'];

        if (!$post_id || !$assetid) {
            return new WP_REST_Response(['error' => 'invalid_request'], 400);
        }

        if (get_post_meta($post_id, 'assetid', true)) {
            return new WP_REST_Response(['error' => 'already_set'], 409);
        }

        update_post_meta($post_id, 'assetid', $assetid);

        return [
            'ok' => true,
            'post_id' => $post_id,
            'assetid' => $assetid
        ];
    }

    public static function lookup($request) {

        $assetid = (int) $request['assetid'];

        $query = new WP_Query([
            'post_type'      => ['page', 'attachment'],
            'meta_key'       => 'assetid',
            'meta_value'     => $assetid,
            'posts_per_page' => 1,
        ]);

        if (!$query->have_posts()) {
            return new WP_REST_Response(['found' => false], 404);
        }

        $post = $query->posts[0];

        return [
            'found'   => true,
            'id'      => $post->ID,
            'type'    => $post->post_type,
            'assetid' => (int) get_post_meta($post->ID, 'assetid', true),
            'link'    => get_permalink($post->ID),
        ];
    }

    /**
     * -------------------------------------------------------
     * CLASSIC ADMIN UI - PAGES
     * -------------------------------------------------------
     */
    public static function register_page_meta_box() {

        add_meta_box(
            'squiz_assetid_page',
            'Asset ID',
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
            'Asset ID',
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

        $value = (int) get_post_meta($post->ID, 'assetid', true);

        echo '<label style="font-weight:600;">Asset ID</label>';
        echo '<input type="number" readonly style="width:100%;margin-top:5px;" value="' . esc_attr($value) . '">';

        echo '<p style="font-size:11px;color:#666;margin-top:6px;">
            Managed externally via Rails (write-once)
        </p>';
    }
}

/**
 * -------------------------------------------------------
 * BOOT STRAP (SAFE)
 * -------------------------------------------------------
 */
add_action('plugins_loaded', ['Squiz', 'boot']);
